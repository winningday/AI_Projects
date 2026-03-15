---
name: make-icon
description: Generate a properly formatted macOS .icns app icon from a source PNG. Use when the user wants to create, fix, or regenerate an app icon.
argument-hint: [source.png] [output.icns]
allowed-tools: Bash, Read, Write, Edit, Glob
---

# macOS App Icon Generator

Generate a properly formatted `.icns` file for macOS apps from a source PNG image.

## When to use

- User wants to create a new app icon
- User has an icon that looks wrong (clipped edges, white borders, blurry)
- User wants to regenerate icons after updating their source image
- User is setting up a new macOS app project

## Icon Design Rules (enforce these when advising the user)

1. **Full square** — design at 1024x1024, NO rounded corners (macOS applies its own squircle mask)
2. **Safe zone** — keep the logo within the center 80% (~100px margin on each side)
3. **Opaque background** — fill the entire square, no transparency at edges
4. **Format** — 32-bit PNG, sRGB or Display P3 color space
5. **Don't round corners yourself** — this causes white/black sliver artifacts when macOS double-masks

## How to generate

Use the `make-icon.sh` script located in the project that needs the icon. The canonical version is at `VoiceTranscriber/make-icon.sh`.

```bash
# Basic — proper square source image
./make-icon.sh <source.png> [output.icns]

# Fix source with baked-in rounded corners
./make-icon.sh --fix-corners <source.png> [output.icns]

# Add safe zone padding (pixels on each side)
./make-icon.sh --padding 100 <source.png> [output.icns]

# Both fixes combined
./make-icon.sh --fix-corners --padding 80 <source.png> [output.icns]
```

## Steps

1. Find the source icon (check for `icon.png` in the project root, or use `$ARGUMENTS`)
2. Validate it's 1024x1024 (warn if not — the script will resize but quality may suffer)
3. Check if the image has rounded corners — if so, use `--fix-corners`
4. Run `make-icon.sh` with appropriate flags
5. Verify the output `.icns` was created
6. If the project has a `build.sh`, confirm it references the generated icon

## If make-icon.sh doesn't exist in the target project

Copy it from `VoiceTranscriber/make-icon.sh` into the target project directory and make it executable:

```bash
cp VoiceTranscriber/make-icon.sh <target-project>/make-icon.sh
chmod +x <target-project>/make-icon.sh
```

## Common issues

| Problem | Cause | Fix |
|---------|-------|-----|
| White/black slivers at edges | Source has baked-in rounded corners | Use `--fix-corners` or redesign as full square |
| Logo clipped by macOS mask | Logo extends to edge of canvas | Use `--padding 100` or redesign with safe zone |
| Blurry at small sizes | Source is too small or has fine details | Start with 1024x1024, simplify details for small sizes |
| Icon not showing in Dock | `CFBundleIconFile` missing from Info.plist | Add `<key>CFBundleIconFile</key><string>AppIcon</string>` |
