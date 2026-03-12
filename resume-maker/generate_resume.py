#!/usr/bin/env python3
"""
Resume Maker — AI-powered resume, cover letter, and interview prep generator.

Usage:
    python generate_resume.py --job "path/to/job_description.txt"
    python generate_resume.py --job "path/to/job_description.txt" --name "John Doe"
    python generate_resume.py --job "path/to/job_description.txt" --about "path/to/ABOUTME.md"
    python generate_resume.py --job "path/to/job_description.txt" --skip-render
    echo "Job description text" | python generate_resume.py --job -

Outputs (in ./outputs/<company>_<date>/):
    <Name>_CV.yaml       — RenderCV YAML (edit then re-render with: rendercv render)
    <Name>_CV.pdf        — Rendered PDF resume
    cover_letter.md      — Tailored cover letter
    interview_prep.md    — Extensive interview preparation guide
"""

import anthropic
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


# ── Constants ──────────────────────────────────────────────────────────────────

ABOUTME_PATH = Path(__file__).parent / "ABOUTME.md"
OUTPUTS_DIR = Path(__file__).parent / "outputs"
MODEL = "claude-opus-4-6"

RENDERCV_YAML_GUIDE = """
RenderCV YAML format reference (use this exact structure):

cv:
  name: Full Name
  location: City, State/Country
  email: email@example.com
  phone: "+1 (555) 123-4567"          # optional
  website: https://example.com         # optional
  social_networks:                     # optional list
    - network: LinkedIn                # LinkedIn | GitHub | Twitter | etc.
      username: username
  sections:
    summary:                           # optional — a short 2-4 line pitch
      - "Your professional summary as a single string here."
    experience:
      - company: Company Name
        position: Job Title
        location: City, State
        start_date: "2021-01"          # YYYY-MM or YYYY
        end_date: "present"            # or YYYY-MM
        highlights:
          - Accomplishment with metric (e.g., "Reduced latency by 40%")
          - Another achievement
    education:
      - institution: University Name
        area: Field of Study
        degree: BS                     # BS | MS | PhD | BA | etc.
        location: City, State
        start_date: "2016"
        end_date: "2020"
        highlights:                    # optional
          - GPA 3.8/4.0
    projects:                          # optional
      - name: Project Name
        date: "2022"                   # or start_date/end_date
        highlights:
          - What it does and impact
    skills:                            # use BulletEntry or TextEntry
      - label: Category
        details: "Skill1, Skill2, Skill3"
    certifications:                    # optional
      - name: Cert Name
        date: "2023"
        highlights:
          - Issuing body

design:
  theme: classic                       # classic | sb2nov | engineeringresumes | moderncv | toberecruited
  page:
    size: us-letter                    # us-letter | a4
    top_margin: "2 cm"
    bottom_margin: "2 cm"
    left_margin: "2 cm"
    right_margin: "2 cm"
  text:
    font_size: "10pt"

locale:
  date_style: "MONTH_ABBREVIATION YEAR"
  phone_number_format: national
"""


# ── Helpers ────────────────────────────────────────────────────────────────────

def print_header(title: str) -> None:
    width = 70
    print(f"\n{'═' * width}")
    print(f"  {title}")
    print(f"{'═' * width}")


def print_section(label: str) -> None:
    print(f"\n── {label} {'─' * (65 - len(label))}")


def stream_claude(client: anthropic.Anthropic, system: str, prompt: str, label: str) -> str:
    """Call Claude with streaming and adaptive thinking; return full text response."""
    print_section(f"Claude: {label}")
    full_text = ""
    in_thinking = False

    with client.messages.stream(
        model=MODEL,
        max_tokens=8192,
        thinking={"type": "adaptive"},
        system=system,
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        for event in stream:
            if event.type == "content_block_start":
                if event.content_block.type == "thinking":
                    in_thinking = True
                    print("  [thinking...]", end="", flush=True)
                elif event.content_block.type == "text":
                    in_thinking = False
                    if full_text == "":
                        print()  # newline after thinking indicator
            elif event.type == "content_block_delta":
                if event.delta.type == "thinking_delta":
                    pass  # suppress thinking content, just show indicator
                elif event.delta.type == "text_delta":
                    print(event.delta.text, end="", flush=True)
                    full_text += event.delta.text
            elif event.type == "content_block_stop":
                in_thinking = False

    print()  # final newline
    return full_text


def extract_yaml_block(text: str) -> str:
    """Extract YAML content from a markdown code block or return the text as-is."""
    # Try ```yaml ... ``` block first
    match = re.search(r"```(?:yaml|YAML)\s*\n(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()
    # Try ``` ... ``` block (no language tag)
    match = re.search(r"```\s*\n(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()
    # Return as-is (Claude may have output raw YAML)
    return text.strip()


def slugify(text: str) -> str:
    """Convert text to a filesystem-safe slug."""
    text = re.sub(r"[^\w\s-]", "", text.lower())
    return re.sub(r"[\s_]+", "-", text).strip("-")[:40]


def render_cv(yaml_path: Path) -> bool:
    """Run rendercv render on the YAML file. Returns True on success."""
    try:
        result = subprocess.run(
            ["rendercv", "render", str(yaml_path)],
            capture_output=True,
            text=True,
            cwd=yaml_path.parent,
        )
        if result.returncode == 0:
            print(f"  ✓ PDF rendered successfully")
            return True
        else:
            print(f"  ✗ rendercv error:\n{result.stderr}")
            print(f"    You can render manually with: rendercv render {yaml_path}")
            return False
    except FileNotFoundError:
        print("  ✗ rendercv not found — install with: pip install 'rendercv[full]'")
        print(f"    Once installed, render with: rendercv render {yaml_path}")
        return False


# ── Prompts ────────────────────────────────────────────────────────────────────

SYSTEM_RESUME_ANALYST = """You are an expert resume writer and career coach with deep expertise in:
- Identifying what makes candidates stand out for specific roles
- Crafting achievement-focused bullet points with quantified impact
- Tailoring content to pass ATS (Applicant Tracking Systems)
- Understanding what hiring managers truly care about

Your goal: create application materials that tell a coherent, compelling story —
each document building intrigue that makes the hiring team eager for the next step."""


def prompt_extract_job_info(job_description: str) -> str:
    return f"""Analyze this job description and extract key information as JSON.

JOB DESCRIPTION:
{job_description}

Return ONLY a JSON object (no markdown, no explanation) with this structure:
{{
  "company": "Company name",
  "role": "Job title",
  "key_skills": ["skill1", "skill2", ...],
  "key_requirements": ["requirement1", "requirement2", ...],
  "nice_to_haves": ["nice1", "nice2", ...],
  "company_values": ["value1", "value2", ...],
  "role_context": "1-2 sentences about what this role is really about"
}}"""


def prompt_select_and_rank(about_me: str, job_info: dict) -> str:
    return f"""You are selecting the BEST content from a candidate's background to match a specific job.

CANDIDATE BACKGROUND:
{about_me}

TARGET JOB:
- Company: {job_info['company']}
- Role: {job_info['role']}
- Key Skills Required: {', '.join(job_info['key_skills'])}
- Key Requirements: {', '.join(job_info['key_requirements'])}
- Nice to Haves: {', '.join(job_info.get('nice_to_haves', []))}
- Company Values: {', '.join(job_info.get('company_values', []))}
- Role Context: {job_info['role_context']}

Your task:
1. Identify the 3-4 most relevant work experiences (be selective — quality over quantity)
2. For each experience, select the 3-5 MOST IMPACTFUL achievements that map to this specific role
3. Identify the most relevant projects/side work (max 2)
4. Curate skills into categories relevant to this role (drop irrelevant ones)
5. Identify the 1-2 most relevant certifications
6. Note any unique differentiators that would make this candidate stand out

Return a structured analysis as JSON:
{{
  "selected_experiences": [
    {{
      "company": "...",
      "role": "...",
      "dates": "...",
      "location": "...",
      "selected_highlights": ["...", "..."],
      "relevance_reason": "why this is included"
    }}
  ],
  "selected_projects": [
    {{
      "name": "...",
      "date": "...",
      "selected_highlights": ["...", "..."]
    }}
  ],
  "curated_skills": [
    {{"label": "Category", "details": "Skill1, Skill2, Skill3"}}
  ],
  "selected_certifications": ["cert1", "cert2"],
  "key_differentiators": ["differentiator1", "differentiator2"],
  "positioning_angle": "The core narrative/angle for this application"
}}"""


def prompt_generate_yaml(
    about_me: str,
    job_info: dict,
    selected_content: dict,
    yaml_guide: str,
) -> str:
    name = re.search(r"\*\*Name:\*\*\s*(.+)", about_me)
    name = name.group(1).strip() if name else "Candidate"

    return f"""Generate a complete RenderCV YAML resume for this candidate targeting the {job_info['role']} role at {job_info['company']}.

CANDIDATE NAME: {name}

POSITIONING ANGLE: {selected_content['positioning_angle']}

KEY DIFFERENTIATORS: {json.dumps(selected_content['key_differentiators'], indent=2)}

SELECTED CONTENT:
{json.dumps(selected_content, indent=2)}

FULL BACKGROUND (for extracting contact details and education):
{about_me}

RENDERCV FORMAT GUIDE:
{yaml_guide}

INSTRUCTIONS:
- Write a powerful 2-3 line summary section that captures the positioning angle
- Use strong action verbs and quantified achievements in all bullet points
- Tailor bullet points to echo language from the job description naturally (not forced)
- Keep to 1 page if possible; maximum 2 pages for senior roles
- Order sections: summary → experience → education → projects (if any) → skills → certifications (if any)
- Use the "classic" theme

Output ONLY the YAML content inside a ```yaml code block. No explanation."""


def prompt_cover_letter(
    about_me: str,
    job_info: dict,
    selected_content: dict,
) -> str:
    name = re.search(r"\*\*Name:\*\*\s*(.+)", about_me)
    name = name.group(1).strip() if name else "Candidate"

    return f"""Write a compelling cover letter for {name} applying for {job_info['role']} at {job_info['company']}.

POSITIONING ANGLE: {selected_content['positioning_angle']}
KEY DIFFERENTIATORS: {json.dumps(selected_content['key_differentiators'], indent=2)}
ROLE CONTEXT: {job_info['role_context']}
COMPANY VALUES: {', '.join(job_info.get('company_values', []))}

BACKGROUND:
{about_me}

COVER LETTER STRATEGY:
This cover letter is the OPENER in a three-part sequence:
1. Cover letter → creates intrigue, makes them WANT to open the resume
2. Resume → provides substance, makes them WANT to meet the candidate
3. Interview → seals the deal

The cover letter should:
- Open with something unexpected/memorable (NOT "I am applying for...")
- Hint at the candidate's strongest differentiator without giving everything away
- Connect the candidate's story to what THIS company is trying to accomplish
- Show genuine research/understanding of the company (based on what's known from the job description)
- End with a confident, specific call to action
- Be SHORT — 3-4 paragraphs max. Every sentence earns its place.
- Sound like a smart human, not a template

Format as clean Markdown. Include the candidate's contact info at the top and today's date ({datetime.now().strftime('%B %d, %Y')})."""


def prompt_interview_prep(
    about_me: str,
    job_info: dict,
    selected_content: dict,
) -> str:
    name = re.search(r"\*\*Name:\*\*\s*(.+)", about_me)
    name = name.group(1).strip() if name else "Candidate"

    return f"""Create a comprehensive interview preparation document for {name} interviewing for {job_info['role']} at {job_info['company']}.

CANDIDATE BACKGROUND:
{about_me}

JOB ANALYSIS:
{json.dumps(job_info, indent=2)}

SELECTED POSITIONING:
- Angle: {selected_content['positioning_angle']}
- Differentiators: {json.dumps(selected_content['key_differentiators'], indent=2)}

Create an EXTENSIVE interview prep document covering:

## 1. Your Core Narrative
- The "story arc" for this application (who you are, why this role, why now)
- Your elevator pitch (30 seconds, 2 minutes, 5 minutes versions)
- How to talk about the resume — what to emphasize, what to gloss over

## 2. Behavioral Questions (STAR format answers)
Cover at least 10 likely behavioral questions for this role, with:
- Full STAR answer tailored to THIS candidate's background
- Alternative stories to use if the first one doesn't land
- Variations of the question to watch for

## 3. Technical / Role-Specific Questions
- 8-12 likely technical questions based on the job requirements
- Framework for answering each
- Key concepts to review beforehand

## 4. "Tell Me About Yourself" Answer
- A polished, tailored version for this specific role

## 5. Questions to Ask the Interviewer
- 5 thoughtful questions that show strategic thinking and genuine curiosity
- 3 questions for the hiring manager
- 3 questions for potential teammates
- 2 questions about the role/company direction

## 6. Handling Tough Questions
- "Why are you leaving your current role?"
- "What's your biggest weakness?"
- "Tell me about a failure"
- "Why do you want to work here?" (vs. competitors)
- Salary/compensation negotiation approach

## 7. Company Research Checklist
- What to know cold before the interview
- Recent news/developments to reference
- How to connect company mission to your values

## 8. Day-Of Checklist
- Mindset and preparation tips
- What to bring / logistics
- How to close each interview round strongly

Format as clean, well-structured Markdown. Be SPECIFIC to this candidate's background — reference actual experiences and achievements from their resume when giving STAR answers."""


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="AI-powered resume, cover letter & interview prep generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--job", "-j",
        required=True,
        metavar="FILE_OR_-",
        help="Path to job description file (or '-' to read from stdin)",
    )
    parser.add_argument(
        "--about", "-a",
        default=str(ABOUTME_PATH),
        metavar="FILE",
        help=f"Path to ABOUTME.md (default: {ABOUTME_PATH})",
    )
    parser.add_argument(
        "--name", "-n",
        default=None,
        metavar="NAME",
        help="Override candidate name (default: read from ABOUTME.md)",
    )
    parser.add_argument(
        "--skip-render",
        action="store_true",
        help="Skip running rendercv (just generate the YAML)",
    )
    parser.add_argument(
        "--theme",
        default="classic",
        choices=["classic", "sb2nov", "engineeringresumes", "moderncv", "toberecruited"],
        help="RenderCV theme (default: classic)",
    )
    args = parser.parse_args()

    # ── Load inputs ──────────────────────────────────────────────────────────

    print_header("Resume Maker — AI-Powered Application Suite")

    # Job description
    if args.job == "-":
        job_description = sys.stdin.read()
    else:
        job_path = Path(args.job)
        if not job_path.exists():
            print(f"Error: Job description file not found: {job_path}", file=sys.stderr)
            sys.exit(1)
        job_description = job_path.read_text(encoding="utf-8")

    if not job_description.strip():
        print("Error: Job description is empty.", file=sys.stderr)
        sys.exit(1)

    # ABOUTME
    about_path = Path(args.about)
    if not about_path.exists():
        print(f"Error: ABOUTME file not found: {about_path}", file=sys.stderr)
        print(f"  Create it at: {about_path}")
        sys.exit(1)
    about_me = about_path.read_text(encoding="utf-8")

    print(f"\n  Job description: {len(job_description)} chars")
    print(f"  About me:        {len(about_me)} chars")

    # ── Init Claude client ────────────────────────────────────────────────────

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("\nError: ANTHROPIC_API_KEY environment variable not set.", file=sys.stderr)
        print("  export ANTHROPIC_API_KEY='your-key-here'")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # ── Step 1: Extract job info ──────────────────────────────────────────────

    print_section("Step 1: Analyzing job description")
    raw_job_info = stream_claude(
        client,
        SYSTEM_RESUME_ANALYST,
        prompt_extract_job_info(job_description),
        "extracting job requirements",
    )

    try:
        # Strip any markdown fences if present
        clean_json = re.sub(r"```(?:json)?\s*\n?", "", raw_job_info).strip().rstrip("```").strip()
        job_info = json.loads(clean_json)
    except json.JSONDecodeError as e:
        print(f"\nWarning: Could not parse job info JSON: {e}")
        print("Using fallback job info.")
        job_info = {
            "company": "Company",
            "role": "Role",
            "key_skills": [],
            "key_requirements": [],
            "nice_to_haves": [],
            "company_values": [],
            "role_context": "See job description.",
        }

    print(f"\n  Company: {job_info.get('company', 'Unknown')}")
    print(f"  Role:    {job_info.get('role', 'Unknown')}")

    # ── Step 2: Select & rank content ─────────────────────────────────────────

    print_section("Step 2: Selecting most relevant content from your background")
    raw_selection = stream_claude(
        client,
        SYSTEM_RESUME_ANALYST,
        prompt_select_and_rank(about_me, job_info),
        "curating your best content for this role",
    )

    try:
        clean_json = re.sub(r"```(?:json)?\s*\n?", "", raw_selection).strip().rstrip("```").strip()
        selected_content = json.loads(clean_json)
    except json.JSONDecodeError as e:
        print(f"\nWarning: Could not parse selection JSON: {e}")
        selected_content = {
            "selected_experiences": [],
            "selected_projects": [],
            "curated_skills": [],
            "selected_certifications": [],
            "key_differentiators": [],
            "positioning_angle": "Experienced professional with relevant skills.",
        }

    print(f"\n  Positioning: {selected_content.get('positioning_angle', '')}")

    # ── Set up output directory ────────────────────────────────────────────────

    company_slug = slugify(job_info.get("company", "company"))
    role_slug = slugify(job_info.get("role", "role"))
    date_str = datetime.now().strftime("%Y-%m-%d")
    out_dir = OUTPUTS_DIR / f"{company_slug}_{role_slug}_{date_str}"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n  Output directory: {out_dir}")

    # ── Determine candidate name ───────────────────────────────────────────────

    if args.name:
        candidate_name = args.name
    else:
        name_match = re.search(r"\*\*Name:\*\*\s*(.+)", about_me)
        candidate_name = name_match.group(1).strip() if name_match else "Candidate"

    name_slug = slugify(candidate_name).replace("-", "_").title().replace("_", "_")
    yaml_filename = f"{candidate_name.replace(' ', '_')}_CV.yaml"

    # ── Step 3: Generate resume YAML ──────────────────────────────────────────

    print_section("Step 3: Generating tailored resume YAML")
    raw_yaml = stream_claude(
        client,
        SYSTEM_RESUME_ANALYST,
        prompt_generate_yaml(about_me, job_info, selected_content, RENDERCV_YAML_GUIDE),
        "crafting your tailored resume",
    )

    yaml_content = extract_yaml_block(raw_yaml)

    # Inject the chosen theme
    if "theme:" in yaml_content:
        yaml_content = re.sub(r"theme:\s*\w+", f"theme: {args.theme}", yaml_content)

    yaml_path = out_dir / yaml_filename
    yaml_path.write_text(yaml_content, encoding="utf-8")
    print(f"\n  ✓ Resume YAML saved: {yaml_path}")

    # ── Step 4: Render PDF ────────────────────────────────────────────────────

    if not args.skip_render:
        print_section("Step 4: Rendering PDF with RenderCV")
        render_cv(yaml_path)
    else:
        print_section("Step 4: Skipping PDF render (--skip-render)")
        print(f"  Run manually: rendercv render \"{yaml_path}\"")

    # ── Step 5: Generate cover letter ─────────────────────────────────────────

    print_section("Step 5: Writing cover letter")
    cover_letter = stream_claude(
        client,
        SYSTEM_RESUME_ANALYST,
        prompt_cover_letter(about_me, job_info, selected_content),
        "crafting your cover letter",
    )

    cover_letter_path = out_dir / "cover_letter.md"
    cover_letter_path.write_text(cover_letter, encoding="utf-8")
    print(f"\n  ✓ Cover letter saved: {cover_letter_path}")

    # ── Step 6: Generate interview prep ───────────────────────────────────────

    print_section("Step 6: Creating interview preparation guide")
    interview_prep = stream_claude(
        client,
        SYSTEM_RESUME_ANALYST,
        prompt_interview_prep(about_me, job_info, selected_content),
        "building your interview prep guide",
    )

    interview_path = out_dir / "interview_prep.md"
    interview_path.write_text(interview_prep, encoding="utf-8")
    print(f"\n  ✓ Interview prep saved: {interview_path}")

    # ── Summary ───────────────────────────────────────────────────────────────

    print_header("Done! Your application suite is ready")
    print(f"""
  📄 Resume YAML:     {yaml_path}
  📄 Cover Letter:    {cover_letter_path}
  📄 Interview Prep:  {interview_path}

  Next steps:
    1. Review and tweak the YAML:  nano "{yaml_path}"
    2. Re-render after edits:      rendercv render "{yaml_path}"
    3. Polish the cover letter:    nano "{cover_letter_path}"
    4. Study interview prep:       cat "{interview_path}" | less

  Good luck! 🚀
""")


if __name__ == "__main__":
    main()
