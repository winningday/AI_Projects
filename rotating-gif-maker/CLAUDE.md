# Rotating GIF Maker

Turns any image into a smooth animated rotating GIF. Great for email signatures,
logos, and headshots. Drop images in `input/`, get GIFs in `output/`.

## Project layout

```
rotating-gif-maker/
├── create_rotating_gif.py   # core script — all logic lives here
├── run.sh                   # convenience wrapper (auto-detects input/)
├── setup.sh                 # one-time venv + dependency install
├── input/                   # drop your source images here
├── output/                  # generated GIFs land here
└── CLAUDE.md                # this file
```

## Setup (first time only)

```bash
cd rotating-gif-maker
bash setup.sh
```

## Skills / slash commands

### /make-gif
Make a rotating GIF from the first image found in `input/`.
Uses the venv automatically.

```bash
bash run.sh
```

### /make-gif-circle
Make a circular rotating GIF (good for headshots / profile pics).

```bash
bash run.sh input/<file> --circle --size 200
```

### /make-gif-logo
Spin a logo PNG that already has transparency.

```bash
bash run.sh input/<file> --size 200 --fps 24 --duration 2
```

### /make-gif-nobg
Remove background first, then spin (requires rembg — installed by setup.sh).

```bash
bash run.sh input/<file> --remove-bg --circle --size 200
```

### /make-gif-slow
Slow, elegant one full rotation over 4 seconds.

```bash
bash run.sh input/<file> --fps 20 --duration 4 --size 200
```

### /make-gif-custom
All options spelled out — edit as needed.

```bash
bash run.sh input/<file> \
  --size 200 \
  --fps 24 \
  --duration 2 \
  --direction cw \
  --circle \
  --remove-bg \
  --output output/my_custom_spin.gif
```

## Key options reference

| Flag | Default | What it does |
|------|---------|-------------|
| `--size N` | 200 | Canvas size in pixels (square) |
| `--fps N` | 24 | Frames per second |
| `--duration N` | 2.0 | Seconds per full rotation |
| `--direction cw\|ccw` | cw | Clockwise or counter-clockwise |
| `--circle` | off | Circular crop mask |
| `--remove-bg` | off | AI background removal (rembg) |
| `--bg-white` | off | Solid white background |
| `--crop W H` | off | Centre-crop before spinning |

## Workflow for a face/headshot

1. Drop photo into `input/`
2. Run: `bash run.sh --remove-bg --circle --size 150`
3. Pick up GIF from `output/`
4. Paste directly into your email signature

## Workflow for a logo

1. Export logo as PNG with transparency from your design tool
2. Drop into `input/`
3. Run: `bash run.sh --size 200 --fps 30 --duration 1.5`
4. Fast, crisp spin in `output/`
