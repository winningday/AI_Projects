You are running the resume maker tool. The user has given you a job description. Your job is to produce a complete, tailored application suite for them.

## The Job Description

$ARGUMENTS

---

## Your Process

Work through these steps carefully and sequentially.

### Step 1 — Read the candidate's background

Read the file at `resume-maker/ABOUTME.md`. This is the candidate's complete career knowledge base.

### Step 2 — Extract structured job information

From the job description above, identify:
- **Company name** and **role title**
- **Key required skills** (must-haves)
- **Key requirements** (experience, responsibilities)
- **Nice-to-haves**
- **Company values** or culture signals
- **Role context**: what problem does this role solve? What does success look like?
- **Tech stack** mentioned

### Step 3 — Select and curate the best content

From the candidate's ABOUTME.md, pick the content that makes the strongest case for *this specific role*:

- **Experiences**: Choose the 3–4 most relevant positions. For each, select the 3–5 bullet points with the highest impact and best alignment to the job requirements. Drop anything that doesn't serve the story.
- **Projects**: Choose at most 2 side projects or open source work that reinforce the candidacy.
- **Skills**: Curate into clean categories relevant to this role. Drop unrelated skills.
- **Certifications**: Only include ones that matter for this role.

Then define a **positioning angle** — the core narrative thread that will run through all three documents. What's the single most compelling thing about this candidate for *this specific role*?

### Step 4 — Generate the RenderCV YAML resume

Create the resume as a RenderCV-compatible YAML file. Use this exact format:

```yaml
cv:
  name: Full Name
  location: City, Country
  email: email@example.com
  phone: "+1 (555) 000-0000"        # include if in ABOUTME
  website: https://example.com       # include if in ABOUTME
  social_networks:
    - network: LinkedIn              # or GitHub, etc.
      username: username
  sections:
    summary:
      - "2–3 line professional summary anchored to the positioning angle and role."
    experience:
      - company: Company Name
        position: Job Title
        location: City, State
        start_date: "2021-01"        # YYYY-MM format
        end_date: "present"          # or YYYY-MM
        highlights:
          - Strong action verb + achievement + metric/impact
          - Another quantified accomplishment
    education:
      - institution: University Name
        area: Field of Study
        degree: BS
        location: City, State
        start_date: "2016"
        end_date: "2020"
        highlights:
          - GPA or notable achievement (only if impressive)
    projects:                         # only if relevant
      - name: Project Name
        date: "2023"
        highlights:
          - What it does and why it matters
    skills:
      - label: Category
        details: "Skill1, Skill2, Skill3"
    certifications:                   # only if relevant
      - name: Certification Name
        date: "2023"

design:
  theme: classic
  page:
    size: us-letter
    top_margin: "2 cm"
    bottom_margin: "2 cm"
    left_margin: "2 cm"
    right_margin: "2 cm"
  text:
    font_size: "10pt"

locale:
  date_style: "MONTH_ABBREVIATION YEAR"
  phone_number_format: national
```

**Resume writing rules:**
- Open with a punchy 2–3 line summary that reflects the positioning angle
- Every bullet point must start with a strong past-tense action verb
- Quantify impact wherever possible (%, $, user counts, time saved, etc.)
- Mirror language from the job description naturally — don't force keywords
- Aim for 1 page; 2 pages max for very senior candidates
- Order: summary → experience → education → projects → skills → certifications

Determine the output directory: `resume-maker/outputs/<company-slug>_<role-slug>_<YYYY-MM-DD>/`
(e.g. `resume-maker/outputs/stripe_senior-software-engineer_2025-01-15/`)

Determine the YAML filename from the candidate's name: `FirstName_LastName_CV.yaml`

Write the YAML file to that path.

### Step 5 — Render the PDF

Run:
```
rendercv render "resume-maker/outputs/<dir>/<Name>_CV.yaml"
```

The PDF will appear in the same directory. If rendercv isn't installed, tell the user to run `pip install "rendercv[full]"` and give them the render command.

### Step 6 — Write the cover letter

The cover letter is the **first act** in a three-part sequence:
- Cover letter → creates intrigue, makes them *want* to open the resume
- Resume → provides proof, makes them *want* to schedule an interview
- Interview → seals the deal

Write a cover letter that:
- **Opens with something memorable** — not "I am writing to apply for..." — something that immediately signals this person is different
- **Hints at the positioning angle** without spelling it out — leave them curious
- **Connects the candidate's story to what this company is trying to accomplish** — show you understand their mission, not just the job description
- **Is SHORT** — 3–4 paragraphs. Every sentence must earn its place.
- **Ends with a confident, specific call to action**
- **Sounds like a smart human**, not a template

Include the candidate's contact info at the top and today's date.

Save as `resume-maker/outputs/<dir>/cover_letter.md`

### Step 7 — Write the interview preparation guide

Create a comprehensive, *candidate-specific* interview prep document. Reference their actual experiences and achievements throughout — no generic advice.

Structure it as:

```markdown
# Interview Prep: [Role] at [Company]

## Your Core Narrative
- The story arc for this application
- 30-second elevator pitch
- 2-minute version
- How to walk through the resume (what to emphasize, what to briefly mention)

## Behavioral Questions
For each of 10+ likely questions:
- Full STAR-format answer using *this candidate's actual experience*
- Alternative story if the first doesn't fit
- Variations of the question to listen for

## Technical / Role-Specific Questions
8–12 questions based on the job requirements, with:
- Framework for answering
- Key concepts to brush up on

## "Tell Me About Yourself"
A polished, tailored version for this specific role.

## Questions to Ask
- 3 for the hiring manager
- 3 for potential teammates
- 2 about company direction / the role's future

## Handling Tough Questions
Specific scripts for:
- "Why are you leaving your current role?"
- "What's your biggest weakness?"
- "Tell me about a failure"
- "Why us, not [competitor]?"
- Compensation discussion approach

## Company Research Checklist
- What to know cold
- Recent news worth referencing
- How to connect their mission to your values

## Day-Of Checklist
- Mindset and preparation
- What to bring / logistics
- How to close each round strongly
```

Save as `resume-maker/outputs/<dir>/interview_prep.md`

### Step 8 — Summary

After completing all steps, show the user:

```
✅ Application suite ready for [Company] — [Role]

📁 resume-maker/outputs/<dir>/
   ├── [Name]_CV.yaml       — Resume YAML (edit & re-render anytime)
   ├── [Name]_CV.pdf        — Rendered PDF
   ├── cover_letter.md      — Cover letter
   └── interview_prep.md    — Interview prep guide

Next steps:
  • Tweak the YAML and re-render:  rendercv render "[Name]_CV.yaml"
  • Read the interview prep out loud — practice the STAR answers
  • Personalize the cover letter closing paragraph in your own voice

Good luck! 🚀
```

---

## Important Notes

- **Be specific to this candidate.** Every document should reference their real experiences, real metrics, real projects — not generic placeholders.
- **The positioning angle is everything.** It should be a single crisp idea that the cover letter hints at, the resume proves, and the interview guide helps them articulate.
- **Quality over completeness.** A tight, focused resume beats a comprehensive one. Cut anything that doesn't serve the story.
- **Don't ask clarifying questions** unless something is critically ambiguous. Make a smart judgment call and execute.
