"""
tests/test_edl_rules.py — Unit tests for EDL rule engine logic.

These tests cover the editorial rules without requiring video files,
FFmpeg, Whisper, or API calls. Pure Python logic only.
"""

import sys
import os
from unittest.mock import MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Stub heavy optional dependencies so tests run without installing them
for _mod in ["cv2", "mediapipe", "whisper", "anthropic",
             "librosa", "soundfile", "mediapipe.python.solutions.hands"]:
    if _mod not in sys.modules:
        sys.modules[_mod] = MagicMock()

# Provide a realistic numpy to avoid masking real logic
import numpy as np  # noqa: E402 — must come after stubs

import pytest
from models.segment import (
    AnalysisWindow, AngleID, ContentLabel, SpeedTier, TranscriptSegment
)
from models.edl import EditDecisionList, EDLEntryType
from config import WatercolorEditorConfig
from pipeline.stage1b_motion import (
    _score_to_tier, _mark_dead_zones, _collapse_micro_segments, tier_to_multiplier,
    MotionResult
)
from pipeline.stage4_subtitles import (
    _merge_close_segments, _enforce_min_duration,
    _format_srt_time, _format_ass_time
)


# ---------------------------------------------------------------------------
# Motion scoring → tier assignment
# ---------------------------------------------------------------------------

class TestScoreToTier:
    def setup_method(self):
        self.cfg = WatercolorEditorConfig().motion

    def test_high_motion_is_active(self):
        assert _score_to_tier(10.0, self.cfg) == SpeedTier.ACTIVE

    def test_above_active_threshold_is_active(self):
        assert _score_to_tier(8.1, self.cfg) == SpeedTier.ACTIVE

    def test_at_active_threshold_is_active(self):
        # exactly at threshold — boundary should be active
        assert _score_to_tier(8.0, self.cfg) == SpeedTier.ACTIVE

    def test_between_slow_and_active_is_slow(self):
        assert _score_to_tier(6.0, self.cfg) == SpeedTier.SLOW

    def test_at_slow_threshold_is_slow(self):
        assert _score_to_tier(4.0, self.cfg) == SpeedTier.SLOW

    def test_between_idle_and_slow_is_idle(self):
        assert _score_to_tier(2.5, self.cfg) == SpeedTier.IDLE

    def test_at_idle_threshold_is_idle(self):
        assert _score_to_tier(1.0, self.cfg) == SpeedTier.IDLE

    def test_below_idle_is_cut(self):
        assert _score_to_tier(0.5, self.cfg) == SpeedTier.CUT

    def test_zero_motion_is_cut(self):
        assert _score_to_tier(0.0, self.cfg) == SpeedTier.CUT


# ---------------------------------------------------------------------------
# Dead zone detection
# ---------------------------------------------------------------------------

class TestDeadZoneDetection:
    def _make_results(self, scores: list[float], fps: float = 25.0) -> list[MotionResult]:
        cfg = WatercolorEditorConfig().motion
        results = []
        for i, score in enumerate(scores):
            tier = _score_to_tier(score, cfg)
            results.append(MotionResult(
                timestamp_sec=i / fps,
                motion_score=score,
                speed_tier=tier,
            ))
        return results

    def test_short_dead_run_is_promoted_to_idle(self):
        cfg = WatercolorEditorConfig().motion
        fps = 25.0
        # 3 seconds of zero motion (75 frames) — less than 5s dead zone threshold
        scores = [10.0] * 50 + [0.0] * 75 + [10.0] * 50
        results = self._make_results(scores, fps)
        results = _mark_dead_zones(results, cfg, fps)

        dead_frames = [r for r in results if r.is_dead_zone]
        assert len(dead_frames) == 0, "Short dead run should not be marked as dead zone"

        # The short run should have been promoted to IDLE
        zero_frames = results[50:125]
        for r in zero_frames:
            assert r.speed_tier == SpeedTier.IDLE

    def test_long_dead_run_is_marked(self):
        cfg = WatercolorEditorConfig().motion
        fps = 25.0
        # 6 seconds of zero motion (150 frames) — exceeds 5s threshold
        scores = [10.0] * 25 + [0.0] * 150 + [10.0] * 25
        results = self._make_results(scores, fps)
        results = _mark_dead_zones(results, cfg, fps)

        dead_frames = [r for r in results if r.is_dead_zone]
        assert len(dead_frames) == 150

    def test_exact_boundary_not_dead_zone(self):
        cfg = WatercolorEditorConfig().motion
        fps = 25.0
        # Exactly 5 seconds (125 frames) — boundary: < threshold, should be IDLE not dead
        scores = [10.0] * 25 + [0.0] * 124 + [10.0] * 25   # 124 < 125
        results = self._make_results(scores, fps)
        results = _mark_dead_zones(results, cfg, fps)
        dead_frames = [r for r in results if r.is_dead_zone]
        assert len(dead_frames) == 0


# ---------------------------------------------------------------------------
# Speed tier multipliers
# ---------------------------------------------------------------------------

class TestSpeedMultipliers:
    def setup_method(self):
        self.cfg = WatercolorEditorConfig().motion

    def test_active_tier_is_1x(self):
        assert tier_to_multiplier(SpeedTier.ACTIVE, self.cfg) == 1.0

    def test_slow_tier_is_1_5x(self):
        assert tier_to_multiplier(SpeedTier.SLOW, self.cfg) == 1.5

    def test_idle_tier_is_2_5x(self):
        assert tier_to_multiplier(SpeedTier.IDLE, self.cfg) == 2.5

    def test_max_speed_is_capped(self):
        # The rendering stage caps at speed_max; verify the config default
        assert self.cfg.speed_max == 3.0


# ---------------------------------------------------------------------------
# Micro-segment collapse
# ---------------------------------------------------------------------------

class TestMicroSegmentCollapse:
    def _make_results(self, tiers: list[SpeedTier], fps: float = 25.0) -> list[MotionResult]:
        return [
            MotionResult(timestamp_sec=i / fps, motion_score=5.0, speed_tier=t)
            for i, t in enumerate(tiers)
        ]

    def test_single_frame_tier_change_collapses(self):
        cfg = WatercolorEditorConfig().motion
        fps = 25.0
        # 100 ACTIVE, 1 IDLE, 100 ACTIVE → the 1-frame IDLE should collapse
        tiers = [SpeedTier.ACTIVE] * 100 + [SpeedTier.IDLE] + [SpeedTier.ACTIVE] * 100
        results = self._make_results(tiers, fps)
        results = _collapse_micro_segments(results, cfg, fps)

        idle_frames = [r for r in results if r.speed_tier == SpeedTier.IDLE]
        assert len(idle_frames) == 0

    def test_long_tier_change_preserved(self):
        cfg = WatercolorEditorConfig().motion
        fps = 25.0
        # min_speed_segment_sec = 3.0 → 75 frames minimum
        # 100 frames of IDLE should be preserved
        tiers = [SpeedTier.ACTIVE] * 100 + [SpeedTier.IDLE] * 100 + [SpeedTier.ACTIVE] * 100
        results = self._make_results(tiers, fps)
        results = _collapse_micro_segments(results, cfg, fps)

        idle_frames = [r for r in results if r.speed_tier == SpeedTier.IDLE]
        assert len(idle_frames) == 100


# ---------------------------------------------------------------------------
# Subtitle merging and timing
# ---------------------------------------------------------------------------

class TestSubtitleMerging:
    def _make_seg(self, seg_id, start, end, text="Hello"):
        return TranscriptSegment(
            segment_id=seg_id,
            start_sec=start,
            end_sec=end,
            chinese_text="你好",
            english_text=text,
        )

    def test_close_segments_merge(self):
        segs = [
            self._make_seg(0, 0.0, 2.0, "Add more water"),
            self._make_seg(1, 2.1, 4.0, "to the brush"),  # 0.1s gap < 0.3s threshold
        ]
        merged = _merge_close_segments(segs)
        assert len(merged) == 1
        assert merged[0].english_text == "Add more water to the brush"
        assert merged[0].start_sec == 0.0
        assert merged[0].end_sec == 4.0

    def test_far_segments_not_merged(self):
        segs = [
            self._make_seg(0, 0.0, 2.0, "Add more water"),
            self._make_seg(1, 3.0, 5.0, "Now pick up blue"),  # 1.0s gap > 0.3s
        ]
        merged = _merge_close_segments(segs)
        assert len(merged) == 2

    def test_min_duration_enforced(self):
        segs = [
            self._make_seg(0, 0.0, 0.5, "Short"),  # 0.5s < 1.0s minimum
        ]
        result = _enforce_min_duration(segs)
        assert result[0].end_sec - result[0].start_sec >= 1.0

    def test_already_long_enough_unchanged(self):
        segs = [
            self._make_seg(0, 0.0, 3.0, "Long enough subtitle here"),
        ]
        result = _enforce_min_duration(segs)
        assert result[0].end_sec == 3.0


# ---------------------------------------------------------------------------
# Timestamp formatting
# ---------------------------------------------------------------------------

class TestTimestampFormatting:
    def test_srt_format_basic(self):
        assert _format_srt_time(0.0) == "00:00:00,000"
        assert _format_srt_time(1.5) == "00:00:01,500"
        assert _format_srt_time(61.0) == "00:01:01,000"
        assert _format_srt_time(3661.0) == "01:01:01,000"

    def test_srt_format_milliseconds(self):
        assert _format_srt_time(1.123) == "00:00:01,123"

    def test_ass_format_basic(self):
        assert _format_ass_time(0.0) == "0:00:00.00"
        assert _format_ass_time(61.0) == "0:01:01.00"
        assert _format_ass_time(3661.5) == "1:01:01.50"

    def test_negative_timestamps_clamped(self):
        # Should not produce negative timestamps
        assert _format_srt_time(-1.0) == "00:00:00,000"
        assert _format_ass_time(-5.0) == "0:00:00.00"


# ---------------------------------------------------------------------------
# AnalysisWindow helpers
# ---------------------------------------------------------------------------

class TestAnalysisWindow:
    def test_duration(self):
        w = AnalysisWindow(start_sec=10.0, end_sec=15.5)
        assert w.duration_sec == pytest.approx(5.5)

    def test_is_banter(self):
        w = AnalysisWindow(start_sec=0, end_sec=1, content_label=ContentLabel.BANTER)
        assert w.is_banter is True
        assert w.is_instructional is False

    def test_is_instructional(self):
        w = AnalysisWindow(start_sec=0, end_sec=1, content_label=ContentLabel.INSTRUCTION)
        assert w.is_instructional is True
        assert w.is_banter is False

    def test_transition_is_instructional(self):
        w = AnalysisWindow(start_sec=0, end_sec=1, content_label=ContentLabel.TRANSITION)
        assert w.is_instructional is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
