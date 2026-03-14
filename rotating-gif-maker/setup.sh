#!/usr/bin/env bash
# Sets up the virtual environment and installs all dependencies.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Creating virtual environment (.venv)…"
python3 -m venv .venv

echo "==> Activating .venv and installing dependencies…"
source .venv/bin/activate

pip install --upgrade pip --quiet
pip install Pillow --quiet

# rembg pulls in onnxruntime which is large; try to install but don't fail.
echo "==> Installing rembg (background removal — may take a moment)…"
pip install rembg onnxruntime --quiet || echo "  [warn] rembg install failed — --remove-bg won't be available."

echo ""
echo "Setup complete!  Run:  source .venv/bin/activate"
echo "Then drop images into input/ and use:  bash run.sh input/yourfile.jpg"
