---
type: readme
scope: youtube-mastermind
purpose: User-facing documentation for the YouTube Mastermind Masterplan system
last_updated: 2026-04-15
---

# YouTube Mastermind Masterplan

An intelligent, persistent YouTube growth system built entirely on Claude Code. Eight specialized agents take you from zero to monetized in 90 days — with full memory, context, and strategic continuity across every session.

---

## How It Works

1. **You fill in one config file** — `channel/config.yaml` — with your niche, goals, and current stats.
2. **You open Claude Code** in this project directory.
3. **Claude reads your channel config and picks up exactly where you left off** (via `MEMORY.md`).
4. **You say what you need** — Claude routes to the right specialist agent.
5. **Every output is saved** to `outputs/` with a date stamp.

---

## The 8 Agents

| # | Agent | What It Does |
|---|-------|-------------|
| 1 | **Channel Blueprint** | Full channel strategy, positioning, content pillars, 90-day roadmap |
| 2 | **Video Idea Machine** | 20 high-potential video ideas with hooks and viral rationale |
| 3 | **Title & Thumbnail** | 10 CTR-optimized title + thumbnail combos per video topic |
| 4 | **Script Builder** | Full video scripts with hook, structure, and CTA |
| 5 | **Shorts Accelerator** | Shorts strategy + 10 ideas + subscriber funnel system |
| 6 | **SEO System** | Complete upload package: title, description, tags, chapters |
| 7 | **Community Builder** | Daily 15-min routine, collab system, loyalty architecture |
| 8 | **Monetization** | Pre-10K revenue: affiliates, products, brand deals, AdSense |

---

## Quick Start

### Step 1 — Fill In Your Config

Open `channel/config.yaml` and complete:
- `channel.niche` — be specific ("personal finance" → "personal finance for US freelancers over 30")
- `channel.target_audience` — who exactly watches your videos
- `channel.unique_angle` — why your channel, not someone else's
- `goals` — your subscriber target, watch hours, and 90-day start date

### Step 2 — Start Claude Code

```bash
cd youtube-mastermind
claude
```

### Step 3 — Run Your First Agent

Say any of the following:
- `"Start my channel blueprint"` → full strategy document
- `"Give me video ideas"` → 20 ideas for your niche
- `"Write my script for [topic]"` → full video script
- `"Where am I in the 90-day plan?"` → progress report

---

## The 90-Day System

### Phase 1: Foundation (Days 1–30)
Focus: `channel-blueprint` → `video-ideas` → `script-builder`
Goal: 8–12 videos published, 100 subscribers, 500 watch hours

### Phase 2: Growth (Days 31–60)
Focus: `title-thumbnail` → `seo-system` → `shorts-accelerator`
Goal: 500 subscribers, 2,000 watch hours, Shorts live

### Phase 3: Monetization (Days 61–90)
Focus: `community-builder` → `monetization` → more `video-ideas`
Goal: 1,000 subscribers, 4,000 watch hours, first revenue

---

## File Structure

```
youtube-mastermind/
├── CLAUDE.md                    ← Master orchestration (Claude reads this first)
├── channel/
│   └── config.yaml              ← YOUR channel data — fill this in
├── .claude/
│   └── agents/
│       ├── channel-blueprint.md
│       ├── video-ideas.md
│       ├── title-thumbnail.md
│       ├── script-builder.md
│       ├── shorts-accelerator.md
│       ├── seo-system.md
│       ├── community-builder.md
│       └── monetization.md
├── outputs/
│   ├── blueprints/              ← Channel strategy documents
│   ├── ideas/                   ← Video idea batches
│   ├── titles/                  ← Title + thumbnail packages
│   ├── scripts/                 ← Full video scripts
│   ├── shorts/                  ← Shorts strategies
│   ├── seo/                     ← SEO packages per video
│   ├── community/               ← Community plans
│   └── monetization/            ← Revenue strategies
├── .context/
│   ├── overview.yaml            ← File map (Claude reads this)
│   └── architecture.yaml        ← Design decisions
├── MEMORY.md                    ← Session log (how Claude remembers)
├── TODO.md                      ← Active tasks
└── README.md                    ← This file
```

---

## Updating Your Stats

After publishing videos or gaining subscribers, tell Claude:

> "Update my stats — I'm at 47 subscribers, 312 watch hours, 3 videos published."

Claude will update `channel/config.yaml` and adjust recommendations based on your current phase.

---

## Session Rules

Claude Code follows these rules automatically (defined in `CLAUDE.md`):
- Always reads your channel config before any advice
- Saves every output to `outputs/` with date stamps
- Updates `MEMORY.md` at the end of every session
- Never gives generic advice — everything is specific to your niche
- One task per session — focused, complete work
