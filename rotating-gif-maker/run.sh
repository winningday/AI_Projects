#!/usr/bin/env bash
# Convenience wrapper — drop an image in input/ and run:
#   bash run.sh input/logo.png
#   bash run.sh input/logo.png --circle --size 150 --remove-bg
#
# All output goes to output/

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INPUT="$1"
if [[ -z "$INPUT" ]]; then
    # Auto-detect first image in input/
    INPUT=$(ls input/*.{jpg,jpeg,png,webp,bmp,tiff} 2>/dev/null | head -1)
    if [[ -z "$INPUT" ]]; then
        echo "Usage: bash run.sh input/<image> [options]"
        echo "   or: drop an image into input/ and run:  bash run.sh"
        exit 1
    fi
    echo "==> Auto-detected input: $INPUT"
fi

# Derive output filename: output/<stem>_rotating.gif
BASENAME=$(basename "$INPUT")
STEM="${BASENAME%.*}"
OUTPUT="output/${STEM}_rotating.gif"

# Activate venv if present
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi

echo "==> Input:  $INPUT"
echo "==> Output: $OUTPUT"
echo ""

# Pass remaining args straight through (e.g. --circle --size 200 --remove-bg)
python3 create_rotating_gif.py \
    --input  "$INPUT" \
    --output "$OUTPUT" \
    "${@:2}"

echo ""
echo "GIF saved to: $OUTPUT"
