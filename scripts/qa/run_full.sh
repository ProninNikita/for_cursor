#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
QA_SEED="${QA_SEED:-12345}"
QA_ACTIONS="${QA_ACTIONS:-80}"
LOG_FILE="/private/tmp/squad_tactics_qa_full.log"

source "${ROOT_DIR}/scripts/qa/qa_shell_common.sh"

set +e
"${GODOT_BIN}" \
  --headless \
  --path "${ROOT_DIR}" \
  --no-header \
  --log-file "${LOG_FILE}" \
  --script res://scripts/qa/qa_runner.gd \
  ++ --scenario full --seed "${QA_SEED}" --actions "${QA_ACTIONS}"
status=$?
set -e

qa_finish_from_log "${status}" "${LOG_FILE}"
