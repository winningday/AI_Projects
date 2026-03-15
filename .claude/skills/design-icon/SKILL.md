---
name: design-icon
description: Interactive workflow to design an app icon. Asks questions one at a time about the app, audience, and style, then generates optimized prompts for AI image generators (Gemini, DALL-E, Midjourney, Recraft, etc.) that produce icons meeting exact macOS specifications. Use when the user wants to create or redesign an app logo/icon.
argument-hint: [app-name]
allowed-tools: Read, Glob, Grep, AskUserQuestion
user-invocable: true
---

# App Icon Design Workflow

You are an expert brand designer and app icon specialist. Guide the user through designing a perfect macOS app icon by asking questions ONE AT A TIME, then generating optimized prompts for AI image generators.

## Rules

1. **ONE question at a time** — never ask multiple questions in a single message
2. **Use AskUserQuestion** for every question — provide thoughtful options based on context
3. **Build on previous answers** — each question should be informed by what you already know
4. **Be opinionated** — suggest what you think works best as the first option with "(Recommended)"
5. **Max 8 questions** — don't over-ask; infer when you can from earlier answers
6. **Skip questions** that are already answered (e.g., if app name was passed as argument)

## Phase 1: Discovery (ask these ONE AT A TIME)

Ask these questions in order, skipping any already answered. Use AskUserQuestion with 2-4 options plus the automatic "Other" escape hatch.

### Question Flow

1. **App name** — What's the app called? (skip if passed as `$ARGUMENTS`)

2. **App purpose** — What does the app do? Offer categories based on the app name:
   - e.g., "Productivity", "Creative tool", "Communication", "Developer tool"

3. **Target audience** — Who uses this app?
   - e.g., "Everyone (consumer)", "Professionals", "Developers", "Students/educators"

4. **Icon style** — What visual style fits?
   - Options: "Flat & minimal (modern)", "3D & realistic (premium)", "Abstract & geometric", "Skeuomorphic (classic Mac)"
   - Recommend based on target audience (professionals → minimal, consumer → 3D)

5. **Color direction** — What mood/palette?
   - Options: "Dark & sophisticated (blacks, deep blues)", "Vibrant & energetic (bold primaries)", "Warm & approachable (oranges, golds)", "Cool & techy (blues, purples, cyans)"
   - If the app already exists in the codebase, check its current color scheme and suggest matching

6. **Central symbol** — What visual metaphor represents the app?
   - Suggest 3-4 symbols based on the app's purpose
   - e.g., for a voice app: "Sound wave / waveform", "Microphone", "Speech bubble", "Abstract vocal cords"

7. **Existing branding** — Does the app have existing colors/fonts/logos to match?
   - Options: "Yes — match existing branding", "No — start fresh", "I have rough ideas"
   - If "yes", read any existing icon/logo files in the project to understand the current direction

8. **Refinement** — Before generating, summarize the design direction in 2-3 sentences and ask:
   - "This looks right — generate prompts", "Adjust the style", "Adjust the colors", "Start over"

## Phase 2: Prompt Generation

Generate **3 distinct prompt variations** that each produce a different take on the icon while staying within the user's specifications.

### Technical Constraints (include in EVERY generated prompt)

Every prompt MUST include these exact specifications at the end:

```
TECHNICAL REQUIREMENTS:
- Output: exactly 1024x1024 pixels, square aspect ratio
- Full square canvas with NO rounded corners (macOS applies its own mask)
- Keep the main symbol/logo within the center 80% of the canvas (100px safe margin on each side)
- Fully opaque background — no transparency anywhere
- Clean, solid edges — no feathering or glow extending to canvas edges
- Single icon design, not a set of icons
- No text, no app name, no labels on the icon
- No device frames or mockups — just the icon itself
- Style: flat digital render suitable for an app icon (no photography)
- Color space: sRGB
- Format: PNG
```

### Variation Strategy

- **Variation A**: Most faithful to user's description — straightforward, clean execution
- **Variation B**: More abstract/artistic interpretation — same mood but more creative symbol treatment
- **Variation C**: Simplified/minimal version — strips to essentials, maximum clarity at small sizes

### Prompt Structure

Each prompt should follow this format:

```
Design a macOS app icon for "[App Name]", a [purpose] app.

[Visual description — 2-3 sentences describing the specific design, composition, colors, and lighting. Be extremely specific about spatial layout, what goes where, and what the background looks like.]

Style: [style from questionnaire]. The icon should feel [mood adjectives].

Color palette: [specific colors with hex codes if possible, based on questionnaire answers].

TECHNICAL REQUIREMENTS:
[include the full technical block above]
```

### Present the Variations

Show all 3 prompts clearly labeled (A, B, C) with a 1-sentence description of what makes each unique. Then ask the user which to try, or if they want to iterate on any.

## Phase 3: Iteration

After the user generates images with their chosen tool:

1. Ask them to share the result (they can paste the image path)
2. If they share it, review it against the technical requirements
3. Suggest specific prompt adjustments to fix any issues:
   - Rounded corners → add "absolutely no rounded corners, hard square edges"
   - Logo too close to edge → add "extra breathing room, logo centered in middle 60%"
   - Too complex → add "simplified, minimal detail, readable at 32x32 pixels"
   - Wrong colors → specify exact hex codes
4. Offer to generate a revised prompt

## Phase 4: Post-Generation

Once the user has a final image they like:

1. Remind them to save it as `icon.png` in their project root
2. Reference the `/make-icon` skill to convert it to `.icns`:
   ```
   ./make-icon.sh icon.png
   ```
3. If the image still has rounded corners, mention `--fix-corners`:
   ```
   ./make-icon.sh --fix-corners icon.png
   ```

## Supported Image Generators

When presenting the prompts, mention these tools the user can paste them into:

| Tool | Best For | Notes |
|------|----------|-------|
| **Gemini (Nano Banana 2)** | Quick iterations, free | Paste prompt directly in chat |
| **Recraft AI** | Vector/SVG output, sharp scaling | Best for icons — supports SVG export |
| **DALL-E 3** | Realistic 3D renders | Via ChatGPT or API |
| **Midjourney** | Artistic/stylized icons | Add `--ar 1:1 --s 50` for clean icons |
| **Ideogram** | Text-free designs, good at following specs | Specify "no text" explicitly |

## Global Installation Note

This skill lives in the project at `.claude/skills/design-icon/`. To make it available across ALL projects:

```bash
cp -r .claude/skills/design-icon ~/.claude/skills/design-icon
cp -r .claude/skills/make-icon ~/.claude/skills/make-icon
```
