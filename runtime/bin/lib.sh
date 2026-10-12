#!/usr/bin/env bash
# Shared runtime helpers. Source this file; do not execute it directly.

set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACKED_PROFILE_DIR="${RUNTIME_ROOT}/profiles"
DEFAULT_PRIVATE_ENV="${HOME}/.config/uncensored-ai/runtime.env"

info() {
  printf '[info] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

resolve_profile_file() {
  local requested="${1:-}"
  local candidate

  [[ -n "${requested}" ]] || die "Profile name or .env path is required."

  if [[ -f "${requested}" ]]; then
    candidate="${requested}"
  elif [[ -f "${TRACKED_PROFILE_DIR}/${requested}" ]]; then
    candidate="${TRACKED_PROFILE_DIR}/${requested}"
  elif [[ -f "${TRACKED_PROFILE_DIR}/${requested}.env" ]]; then
    candidate="${TRACKED_PROFILE_DIR}/${requested}.env"
  else
    die "Profile not found: ${requested}"
  fi

  (
    cd "$(dirname "${candidate}")"
    printf '%s/%s\n' "$PWD" "$(basename "${candidate}")"
  )
}

load_profile() {
  local requested="${1:-}"
  local original_profile_name
  local original_engine
  local original_engine_version
  local original_model_id
  local revision_override_file
  local local_override_file

  PROFILE_FILE="$(resolve_profile_file "${requested}")"

  set -a
  # shellcheck disable=SC1090
  source "${PROFILE_FILE}"
  set +a

  : "${PROFILE_NAME:?PROFILE_NAME is missing from ${PROFILE_FILE}}"
  : "${ENGINE:?ENGINE is missing from ${PROFILE_FILE}}"
  : "${ENGINE_VERSION:?ENGINE_VERSION is missing from ${PROFILE_FILE}}"
  : "${MODEL_ID:?MODEL_ID is missing from ${PROFILE_FILE}}"

  original_profile_name="${PROFILE_NAME}"
  original_engine="${ENGINE}"
  original_engine_version="${ENGINE_VERSION}"
  original_model_id="${MODEL_ID}"

  PRIVATE_ENV_FILE="${UNCENSORED_AI_ENV_FILE:-${DEFAULT_PRIVATE_ENV}}"
  if [[ -f "${PRIVATE_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${PRIVATE_ENV_FILE}"
    set +a
  fi

  PROFILE_OVERRIDE_DIR="${PROFILE_OVERRIDE_DIR:-${HOME}/.config/uncensored-ai/profiles}"
  revision_override_file="${PROFILE_OVERRIDE_DIR}/${original_profile_name}.revision.env"
  if [[ -f "${revision_override_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${revision_override_file}"
    set +a
  fi

  local_override_file="${PROFILE_OVERRIDE_DIR}/${original_profile_name}.local.env"
  if [[ -f "${local_override_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${local_override_file}"
    set +a
  fi

  [[ "${PROFILE_NAME}" == "${original_profile_name}" ]] ||
    die "A local override may not change PROFILE_NAME."
  [[ "${ENGINE}" == "${original_engine}" ]] ||
    die "A local override may not change ENGINE."
  [[ "${ENGINE_VERSION}" == "${original_engine_version}" ]] ||
    die "A local override may not change ENGINE_VERSION."
  [[ "${MODEL_ID}" == "${original_model_id}" ]] ||
    die "A local override may not change MODEL_ID."

  DATA_ROOT="${DATA_ROOT:-${HOME}/.local/share/uncensored-ai}"
  MODEL_STORE="${MODEL_STORE:-${DATA_ROOT}/models}"
  ENGINE_VENV_ROOT="${ENGINE_VENV_ROOT:-${DATA_ROOT}/venvs}"
  LOG_ROOT="${LOG_ROOT:-${DATA_ROOT}/logs}"
  RUN_ROOT="${RUN_ROOT:-${DATA_ROOT}/run}"
  START_POWER_LOG="${START_POWER_LOG:-1}"
  STARTUP_TIMEOUT_SECONDS="${STARTUP_TIMEOUT_SECONDS:-900}"
  SUPERVISOR_MAX_RESTARTS="${SUPERVISOR_MAX_RESTARTS:-2}"
  SUPERVISOR_RESTART_DELAY_SECONDS="${SUPERVISOR_RESTART_DELAY_SECONDS:-5}"
  ALLOW_REMOTE_CODE="${ALLOW_REMOTE_CODE:-0}"
  API_KEY="${API_KEY:-}"
  HF_TOKEN="${HF_TOKEN:-}"

  BIND_HOST="${BIND_HOST:-127.0.0.1}"
  PORT="${PORT:-8000}"
  SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-local-model}"
  TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-0}"
  SPECULATIVE_DECODING="${SPECULATIVE_DECODING:-0}"

  MODEL_REVISION="${MODEL_REVISION:-REPLACE_WITH_FULL_COMMIT_SHA}"
  MODEL_DIR="${MODEL_STORE}/${PROFILE_NAME}/${MODEL_REVISION}"

  export PROFILE_FILE PRIVATE_ENV_FILE PROFILE_OVERRIDE_DIR
  export DATA_ROOT MODEL_STORE ENGINE_VENV_ROOT LOG_ROOT RUN_ROOT
  export MODEL_DIR API_KEY HF_TOKEN
}

validate_revision() {
  [[ "${MODEL_REVISION}" =~ ^[0-9a-fA-F]{40}$ ]] ||
    die "MODEL_REVISION must be a full 40-character commit SHA. Run pin-revision.sh first."
}

validate_profile() {
  [[ "${PROFILE_NAME}" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "Unsafe PROFILE_NAME: ${PROFILE_NAME}"

  case "${ENGINE}" in
    sglang|vllm) ;;
    *) die "Unsupported ENGINE: ${ENGINE}" ;;
  esac

  [[ "${BIND_HOST}" == "127.0.0.1" ]] ||
    die "Refusing non-loopback BIND_HOST=${BIND_HOST}."
  [[ "${PORT}" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) ||
    die "Invalid PORT=${PORT}."
  [[ "${TRUST_REMOTE_CODE}" == "0" || "${TRUST_REMOTE_CODE}" == "1" ]] ||
    die "TRUST_REMOTE_CODE must be 0 or 1."
  [[ "${SPECULATIVE_DECODING}" == "0" || "${SPECULATIVE_DECODING}" == "1" ]] ||
    die "SPECULATIVE_DECODING must be 0 or 1."

  if [[ "${TRUST_REMOTE_CODE}" == "1" && "${ALLOW_REMOTE_CODE}" != "1" ]]; then
    die "Remote code needs both TRUST_REMOTE_CODE=1 and ALLOW_REMOTE_CODE=1 in local, untracked configuration."
  fi
}

require_runtime_secrets() {
  [[ -f "${PRIVATE_ENV_FILE}" ]] ||
    die "Private runtime file is missing: ${PRIVATE_ENV_FILE}"

  if command -v stat >/dev/null 2>&1; then
    local mode
    local group_other
    mode="$(stat -c '%a' "${PRIVATE_ENV_FILE}")"
    group_other="${mode: -2}"
    (( 8#${group_other} == 0 )) ||
      die "${PRIVATE_ENV_FILE} must not be readable or writable by group/other; run chmod 600."
  fi

  [[ -n "${API_KEY}" ]] || die "API_KEY is empty in ${PRIVATE_ENV_FILE}."
  [[ "${API_KEY}" != REPLACE_* ]] ||
    die "API_KEY is still a placeholder in ${PRIVATE_ENV_FILE}."
  (( ${#API_KEY} >= 32 )) ||
    die "API_KEY must contain at least 32 characters."

  if [[ "${GATED_REPOSITORY:-0}" == "1" && -z "${HF_TOKEN}" ]]; then
    die "This gated repository needs a read-only HF_TOKEN in ${PRIVATE_ENV_FILE}."
  fi
}

engine_python_path() {
  if [[ -n "${ENGINE_PYTHON:-}" ]]; then
    printf '%s\n' "${ENGINE_PYTHON}"
  else
    printf '%s/%s-%s/bin/python\n' "${ENGINE_VENV_ROOT}" "${ENGINE}" "${ENGINE_VERSION}"
  fi
}

engine_binary_path() {
  local variable_name
  local override=""

  case "${ENGINE}" in
    sglang) variable_name="SGLANG_BIN" ;;
    vllm) variable_name="VLLM_BIN" ;;
  esac

  override="${!variable_name:-}"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
  else
    printf '%s/%s-%s/bin/%s\n' \
      "${ENGINE_VENV_ROOT}" "${ENGINE}" "${ENGINE_VERSION}" "${ENGINE}"
  fi
}

assert_engine_version() {
  local python_bin
  local actual_version

  python_bin="$(engine_python_path)"
  [[ -x "${python_bin}" ]] ||
    die "Engine environment is missing: ${python_bin}. Run install-engine.sh ${PROFILE_NAME}."

  actual_version="$(
    "${python_bin}" -c \
      'import importlib.metadata as m, sys; print(m.version(sys.argv[1]))' \
      "${ENGINE}"
  )"

  [[ "${actual_version}" == "${ENGINE_VERSION}" ]] ||
    die "Expected ${ENGINE} ${ENGINE_VERSION}, found ${actual_version}."
}

require_model_dir() {
  [[ -d "${MODEL_DIR}" ]] ||
    die "Pinned model directory is missing: ${MODEL_DIR}. Run download-model.sh ${PROFILE_NAME}."
  [[ -f "${MODEL_DIR}/config.json" ]] ||
    die "Downloaded model has no config.json: ${MODEL_DIR}"
  find "${MODEL_DIR}" -maxdepth 2 -type f -name '*.safetensors' -print -quit |
    grep -q . ||
    die "No safetensors weights found under ${MODEL_DIR}."
}

profile_state_dir() {
  printf '%s/%s\n' "${RUN_ROOT}" "${PROFILE_NAME}"
}

profile_log_dir() {
  printf '%s/%s\n' "${LOG_ROOT}" "${PROFILE_NAME}"
}
