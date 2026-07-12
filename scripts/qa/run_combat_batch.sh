#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
QA_SEED="${QA_SEED:-12345}"
QA_COUNT="${QA_COUNT:-100}"
QA_OUTPUT_JSON="${QA_OUTPUT_JSON:-${ROOT_DIR}/data/rt_combat_batch_report.json}"
QA_OUTPUT_CSV="${QA_OUTPUT_CSV:-${ROOT_DIR}/data/rt_combat_batch_report.csv}"
QA_SUITE="${QA_SUITE:-training}"
LOG_FILE="/private/tmp/squad_tactics_combat_batch.log"

source "${ROOT_DIR}/scripts/qa/qa_shell_common.sh"

set +e
"${GODOT_BIN}" \
  --headless \
  --path "${ROOT_DIR}" \
  --no-header \
  --log-file "${LOG_FILE}" \
  --script res://scripts/qa/rt_combat_batch_runner.gd \
  ++ --suite "${QA_SUITE}" --count "${QA_COUNT}" --seed "${QA_SEED}" --output-json "${QA_OUTPUT_JSON}" --output-csv "${QA_OUTPUT_CSV}"
status=$?
set -e

qa_finish_from_log "${status}" "${LOG_FILE}"
