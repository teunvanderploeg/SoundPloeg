#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="${SOUNDPLOEG_SUPPORT_DIR:-$HOME/Library/Application Support/SoundPloeg}"
MODEL_DIR="${SOUNDPLOEG_MODEL_DIR:-$APP_SUPPORT/models}"
VENV_DIR="$APP_SUPPORT/tts-venv"

if [[ -n "${SOUNDPLOEG_PYTHON:-}" ]]; then
  PYTHON="$SOUNDPLOEG_PYTHON"
elif command -v python3.12 >/dev/null 2>&1; then
  PYTHON="$(command -v python3.12)"
else
  PYTHON="$(command -v python3)"
fi
"$PYTHON" -c 'import sys; assert (3, 10) <= sys.version_info < (3, 14), "Use Python 3.10–3.13. Set SOUNDPLOEG_PYTHON to its path."'
mkdir -p "$APP_SUPPORT" "$MODEL_DIR"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  "$PYTHON" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install -r "$SCRIPT_DIR/tts-requirements.txt"
"$VENV_DIR/bin/python" "$SCRIPT_DIR/install_models.py" --root "$MODEL_DIR" --remove-legacy
printf 'Speech setup complete. Models: %s\n' "$MODEL_DIR"
