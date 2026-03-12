# Resume Maker — AI-Powered Application Suite

Give it a job description. Get back a tailored resume, cover letter, and interview prep guide — all in minutes.

## How It Works

The tool follows a three-act strategy:

| Document | Purpose |
|---|---|
| **Cover Letter** | Soft opener that creates intrigue — makes them *want* to open your resume |
| **Resume (PDF)** | Adds substance and proof — makes them *want* to meet you |
| **Interview Prep** | Seals the deal — extensive guide for turning conversations into offers |

Claude (claude-opus-4-6 with adaptive thinking) reads your `ABOUTME.md` knowledge base and the job description, then selects and arranges your best bits to tell the most compelling story for *that specific role*.

## Setup

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

Or install individually:
```bash
pip install anthropic
pip install "rendercv[full]"
```

### 2. Set your API key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Add it to your shell profile (`~/.bashrc`, `~/.zshrc`) to persist it.

### 3. Fill in your ABOUTME.md

Open `ABOUTME.md` and replace the example content with your real background. **More detail is better** — Claude will pick the most relevant parts. Keep adding to it as you gain new experience.

The file should include:
- Personal info (name, email, location, LinkedIn, GitHub)
- Work history with specific achievements and metrics
- Education
- Skills (organized by category)
- Projects and side work
- Certifications, talks, publications
- What you're looking for in your next role

## Usage

### Basic

```bash
python generate_resume.py --job example_job.txt
```

### With options

```bash
# Use a different ABOUTME file
python generate_resume.py --job job.txt --about ~/my_cv_data.md

# Override candidate name
python generate_resume.py --job job.txt --name "Jane Smith"

# Choose a different resume theme
python generate_resume.py --job job.txt --theme sb2nov

# Skip rendering (just generate YAML, render manually later)
python generate_resume.py --job job.txt --skip-render

# Read job description from stdin
pbpaste | python generate_resume.py --job -
cat job.txt | python generate_resume.py --job -
```

### Piping job descriptions

Copy a job posting from a browser, then:
```bash
# macOS
pbpaste | python generate_resume.py --job -

# Linux (from clipboard)
xclip -o | python generate_resume.py --job -
```

## Output

All files are saved to `outputs/<company>_<role>_<date>/`:

```
outputs/
└── stripe_senior-software-engineer_2025-01-15/
    ├── Jane_Doe_CV.yaml       ← Edit this, then re-render
    ├── Jane_Doe_CV.pdf        ← Rendered resume (via rendercv)
    ├── cover_letter.md        ← Tailored cover letter
    └── interview_prep.md      ← Extensive interview guide
```

## Editing Your Resume

The YAML is designed to be easy to tweak. After editing:

```bash
rendercv render outputs/stripe_.../Jane_Doe_CV.yaml
```

### Available Themes

| Theme | Style |
|---|---|
| `classic` | Clean, traditional (default) |
| `sb2nov` | Modern, minimal |
| `engineeringresumes` | Tech-focused |
| `moderncv` | Contemporary with color accents |
| `toberecruited` | Bold, modern |

Preview themes at: https://docs.rendercv.com/themes/

## Tips for Best Results

1. **More detail in ABOUTME.md = better output.** Include metrics, context, and impact for every achievement.

2. **Update ABOUTME.md after every project**, not just when job hunting. Fresh details are easy to add but hard to reconstruct later.

3. **Review the YAML before sending.** Claude is good but not perfect — check dates, names, and phrasing.

4. **Tweak the cover letter voice** to sound more like you. The structure will be strong; the personality is yours to add.

5. **Actually read the interview prep.** The STAR answers are tailored to your background — practice saying them out loud.

6. **Re-run for each application.** Even similar roles at different companies call for different positioning.

## File Structure

```
resume-maker/
├── generate_resume.py    ← Main script
├── ABOUTME.md            ← Your career knowledge base (edit this!)
├── requirements.txt      ← Python dependencies
├── example_job.txt       ← Sample job description for testing
├── outputs/              ← Generated files (gitignored)
└── README.md
```
