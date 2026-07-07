#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
QA_SEED="${QA_SEED:-12345}"

"${GODOT_BIN}" \
  --headless \
  --path "${ROOT_DIR}" \
  --no-header \
  --log-file /private/tmp/squad_tactics_qa_smoke.log \
  --script res://scripts/qa/qa_runner.gd \
  ++ --scenario smoke_all --seed "${QA_SEED}"
