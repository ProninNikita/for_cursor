#!/usr/bin/env bash

qa_log_error_lines() {
  local log_file="$1"
  if [[ ! -f "${log_file}" ]]; then
    return 1
  fi

  grep -E \
    "SCRIPT ERROR:|Parse Error:|Compile Error:|Invalid assignment|Invalid call|Invalid get index|Trying to assign|Cannot call method|Attempt to call|BATCH_DONE: FAIL|QA_DONE: FAIL" \
    "${log_file}" \
    | grep -v "get_system_ca_certificates" \
    | grep -v "ObjectDB instances leaked" \
    | grep -v "Resources still in use" || true
}

qa_finish_from_log() {
  local status="$1"
  local log_file="$2"

  if [[ "${status}" -ne 0 ]]; then
    exit "${status}"
  fi

  local errors
  errors="$(qa_log_error_lines "${log_file}")"
  if [[ -n "${errors}" ]]; then
    echo "QA_LOG_ERRORS:"
    echo "${errors}"
    exit 1
  fi
}
