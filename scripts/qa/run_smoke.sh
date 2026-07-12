#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
QA_SEED="${QA_SEED:-12345}"
LOG_FILE="/private/tmp/squad_tactics_qa_smoke.log"

source "${ROOT_DIR}/scripts/qa/qa_shell_common.sh"

set +e
"${GODOT_BIN}" \
  --headless \
  --path "${ROOT_DIR}" \
  --no-header \
  --log-file "${LOG_FILE}" \
  --script res://scripts/qa/qa_runner.gd \
  ++ --scenario smoke_all --seed "${QA_SEED}"
status=$?
set -e

qa_finish_from_log "${status}" "${LOG_FILE}"
