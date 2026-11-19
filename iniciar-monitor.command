#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"
# docker compose up --build -d  # Descomente se quiser usar a página web.
if [ ! -x "$PROJECT_DIR/CodexPulse.app/Contents/MacOS/CodexPulse" ]; then
  "$PROJECT_DIR/build-macos-app.sh"
fi
open "$PROJECT_DIR/CodexPulse.app"
