"""
pipeline/stage1c_audio.py — Stage 1C: ASR, content classification, translation.

Three sub-tasks run sequentially:

  1. TRANSCRIPTION  — Whisper extracts Chinese text + word-level timestamps
  2. CLASSIFICATION — Claude labels each segment (INSTRUCTION / BANTER / etc.)
  3. TRANSLATION    — Claude translates instructional segments to English
                      with art-terminology awareness

Design notes:
  - Whisper is run once on the primary audio track (not per-angle).
  - Classification is batched (N segments per API call) to balance
    latency vs. cost.
  - Translation carries the previous 3 sentences as context so Claude
    understands flow and doesn't translate idioms out of context.
  - All three results are attached to TranscriptSegment objects and
    returned as a single list.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

import anthropic

from config import WatercolorEditorConfig
from models.segment import ContentLabel, TranscriptSegment, TranscriptWord

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def run_audio_pipeline(
    config: WatercolorEditorConfig,
    audio_source_path: str,
    start_offset_sec: float = 0.0,
) -> list[TranscriptSegment]:
    """
    Full Stage 1C pipeline: transcribe → classify → translate.

    audio_source_path: path to the video/audio file carrying primary audio.
    start_offset_sec: sync offset so segment timestamps are in shared timeline.

    Returns a list of TranscriptSegment with chinese_text, content_label,
    and english_text populated.
    """
    log.info("Stage 1C: Starting audio pipeline")

    # Step 1: Transcription
    segments = transcribe(config, audio_source_path, start_offset_sec)
    log.info(f"Transcription complete: {len(segments)} segments")

    # Step 2: Classification
    segments = classify_content(config, segments)
    log.info(f"Classification complete")

    # Step 3: Translation (instructional segments only)
    segments = translate_segments(config, segments)
    log.info(f"Translation complete")

    return segments


# ---------------------------------------------------------------------------
# Step 1: Transcription with Whisper
# ---------------------------------------------------------------------------

def transcribe(
    config: WatercolorEditorConfig,
    video_path: str,
    start_offset_sec: float = 0.0,
) -> list[TranscriptSegment]:
    """
    Run Whisper on the audio track and return timed TranscriptSegment objects.
    """
    cfg = config.audio
    audio_path = _extract_audio_for_whisper(video_path)

    try:
        import whisper
    except ImportError:
        raise ImportError(
            "openai-whisper is required. Install with: pip install openai-whisper"
        )

    log.info(f"Loading Whisper model: {cfg.whisper_model}")
    model = whisper.load_model(cfg.whisper_model)

    log.info(f"Transcribing {video_path} (language: {cfg.whisper_language})")
    result = model.transcribe(
        audio_path,
        language=cfg.whisper_language,
        word_timestamps=cfg.whisper_word_timestamps,
        verbose=False,
    )

    segments: list[TranscriptSegment] = []
    for i, seg in enumerate(result.get("segments", [])):
        words: list[TranscriptWord] = []
        for w in seg.get("words", []):
            words.append(TranscriptWord(
                word=w["word"],
                start_sec=w["start"] - start_offset_sec,
                end_sec=w["end"] - start_offset_sec,
                confidence=w.get("probability", 1.0),
            ))

        segments.append(TranscriptSegment(
            segment_id=i,
            start_sec=seg["start"] - start_offset_sec,
            end_sec=seg["end"] - start_offset_sec,
            chinese_text=seg["text"].strip(),
            words=words,
        ))

    # Clean up temp audio file
    Path(audio_path).unlink(missing_ok=True)
    return segments


def _extract_audio_for_whisper(video_path: str) -> str:
    """Extract audio to a temporary 16kHz mono WAV file for Whisper."""
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        tmp.name,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return tmp.name


# ---------------------------------------------------------------------------
# Step 2: Content classification via Claude
# ---------------------------------------------------------------------------

_CLASSIFICATION_SYSTEM = """\
You are classifying segments from a live watercolor painting class recorded in Chinese.
The class was taught live so it includes both instructional content and informal conversation.

For each segment, assign exactly one label:
- INSTRUCTION: painting technique, color mixing, brush handling, compositional advice,
               explaining what the teacher is doing or why
- TRANSITION:  asking if students understand, moving between topics, describing what
               comes next, setup or preparation statements
- BANTER:      greetings, small talk, jokes, off-topic conversation, comments about
               food/weather/personal life, asking about others' wellbeing
- SILENCE:     filler words only (嗯, 啊, 哦), very short non-verbal sounds, pauses

Respond with a JSON array matching the input order, each object having:
  {"id": <segment_id>, "label": "<LABEL>", "confidence": <0.0-1.0>}

No explanation needed — JSON only."""

_CLASSIFICATION_USER_TEMPLATE = """\
Classify these {n} transcript segments from a watercolor class:

{segments_json}"""


def classify_content(
    config: WatercolorEditorConfig,
    segments: list[TranscriptSegment],
) -> list[TranscriptSegment]:
    """
    Send segments to Claude in batches for content classification.
    Returns the same list with content_label and label_confidence populated.
    """
    cfg = config.audio
    client = anthropic.Anthropic()

    batch_size = cfg.classification_batch_size
    batches = [
        segments[i: i + batch_size]
        for i in range(0, len(segments), batch_size)
    ]

    for batch_idx, batch in enumerate(batches):
        log.info(
            f"Classifying batch {batch_idx + 1}/{len(batches)} "
            f"({len(batch)} segments)"
        )
        _classify_batch(client, batch, cfg)

    return segments


def _classify_batch(
    client: anthropic.Anthropic,
    batch: list[TranscriptSegment],
    cfg,
) -> None:
    """Classify a single batch in-place."""
    segments_input = [
        {
            "id": seg.segment_id,
            "start": round(seg.start_sec, 2),
            "end": round(seg.end_sec, 2),
            "text": seg.chinese_text,
        }
        for seg in batch
    ]

    user_content = _CLASSIFICATION_USER_TEMPLATE.format(
        n=len(batch),
        segments_json=json.dumps(segments_input, ensure_ascii=False, indent=2),
    )

    response = client.messages.create(
        model=cfg.claude_model,
        max_tokens=1024,
        system=_CLASSIFICATION_SYSTEM,
        messages=[{"role": "user", "content": user_content}],
    )

    raw = response.content[0].text.strip()
    # Strip markdown code fences if present
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    raw = raw.strip()

    try:
        classifications = json.loads(raw)
    except json.JSONDecodeError as e:
        log.error(f"Failed to parse classification response: {e}\nRaw: {raw}")
        # Fallback: label everything as INSTRUCTION to be safe
        for seg in batch:
            seg.content_label = ContentLabel.INSTRUCTION
            seg.label_confidence = 0.0
        return

    id_to_result = {item["id"]: item for item in classifications}

    for seg in batch:
        result = id_to_result.get(seg.segment_id)
        if result:
            try:
                seg.content_label = ContentLabel(result["label"])
            except ValueError:
                seg.content_label = ContentLabel.INSTRUCTION
            seg.label_confidence = float(result.get("confidence", 0.8))
        else:
            seg.content_label = ContentLabel.INSTRUCTION
            seg.label_confidence = 0.0


# ---------------------------------------------------------------------------
# Step 3: Translation via Claude
# ---------------------------------------------------------------------------

_TRANSLATION_SYSTEM = """\
You are translating live watercolor painting instruction from Chinese to English.

Guidelines:
- Preserve art terminology precisely (brush types, color names, pigment properties,
  techniques like wet-on-wet, glazing, lifting, blooming)
- Use the imperative mood for instructions: "Add more water" not "More water is added"
- Preserve pacing cues: "Slowly... like this..." "Very lightly here"
- Keep the teacher's personal style — casual but authoritative
- Do NOT translate banter segments (they will be marked SKIP)
- For each segment, output ONLY the English translation, one per line
- Match the order and count of input segments exactly

Respond with a JSON array in the same order as input:
  [{"id": <segment_id>, "english": "<translation>"}]"""

_TRANSLATION_USER_TEMPLATE = """\
Current painting stage context: {stage_context}

Previous sentences (for context, do not translate):
{previous_context}

Translate these {n} segments:
{segments_json}"""

_CONTEXT_WINDOW = 3   # Number of previous translated sentences to include


def translate_segments(
    config: WatercolorEditorConfig,
    segments: list[TranscriptSegment],
) -> list[TranscriptSegment]:
    """
    Translate instructional/transition segments to English.
    Banter and silence segments are skipped (english_text left as None).

    Context-aware: passes the previous N translated sentences to each batch.
    """
    cfg = config.audio
    client = anthropic.Anthropic()

    batch_size = cfg.classification_batch_size
    translated_context: list[str] = []   # rolling buffer of recent translations

    # Only translate instructional content
    translatable_labels = {ContentLabel.INSTRUCTION, ContentLabel.TRANSITION}

    i = 0
    while i < len(segments):
        # Build a batch of translatable segments
        batch: list[TranscriptSegment] = []
        j = i
        while j < len(segments) and len(batch) < batch_size:
            if segments[j].content_label in translatable_labels:
                batch.append(segments[j])
            j += 1

        if not batch:
            i = j
            continue

        log.info(
            f"Translating segments {batch[0].segment_id}–{batch[-1].segment_id}"
        )

        new_translations = _translate_batch(
            client, batch, cfg, translated_context
        )

        # Update rolling context
        translated_context.extend(new_translations)
        if len(translated_context) > _CONTEXT_WINDOW:
            translated_context = translated_context[-_CONTEXT_WINDOW:]

        i = j

    return segments


def _translate_batch(
    client: anthropic.Anthropic,
    batch: list[TranscriptSegment],
    cfg,
    context: list[str],
) -> list[str]:
    """
    Translate a batch of segments. Returns a list of English strings
    (one per segment, in order). Populates segment.english_text in-place.
    """
    segments_input = [
        {"id": seg.segment_id, "chinese": seg.chinese_text}
        for seg in batch
    ]

    previous_context = (
        "\n".join(f"  - {s}" for s in context) if context
        else "  (start of session)"
    )

    # Infer stage context from technique tags or segment position
    stage_context = _infer_stage_context(batch)

    user_content = _TRANSLATION_USER_TEMPLATE.format(
        stage_context=stage_context,
        previous_context=previous_context,
        n=len(batch),
        segments_json=json.dumps(segments_input, ensure_ascii=False, indent=2),
    )

    response = client.messages.create(
        model=cfg.claude_model,
        max_tokens=2048,
        system=_TRANSLATION_SYSTEM,
        messages=[{"role": "user", "content": user_content}],
    )

    raw = response.content[0].text.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    raw = raw.strip()

    new_translations: list[str] = []
    try:
        results = json.loads(raw)
        id_to_translation = {item["id"]: item["english"] for item in results}
        for seg in batch:
            translation = id_to_translation.get(seg.segment_id, "")
            seg.english_text = translation.strip()
            new_translations.append(seg.english_text)
    except (json.JSONDecodeError, KeyError) as e:
        log.error(f"Translation parse error: {e}\nRaw: {raw}")
        # Fallback: mark as untranslated
        for seg in batch:
            seg.english_text = f"[Translation unavailable: {seg.chinese_text}]"
            new_translations.append(seg.english_text)

    return new_translations


def _infer_stage_context(batch: list[TranscriptSegment]) -> str:
    """
    Produce a brief description of the current painting stage for the
    translation prompt. Uses technique tags if available, otherwise
    estimates from position in the session.
    """
    tags = [seg.technique_tag for seg in batch if seg.technique_tag]
    if tags:
        return f"Currently demonstrating: {', '.join(set(tags))}"

    # Estimate from timestamp
    avg_time = (batch[0].start_sec + batch[-1].end_sec) / 2
    minutes = avg_time / 60
    if minutes < 10:
        return "Introduction and initial wash stage"
    elif minutes < 30:
        return "Main painting stage — building up layers"
    else:
        return "Detail and finishing stage"
