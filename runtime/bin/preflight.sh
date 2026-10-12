#!/usr/bin/env bash
# Validate host, storage, privacy, and engine prerequisites before launching one profile.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
validate_revision
require_runtime_secrets
assert_engine_version
require_model_dir

need_command awk
need_command df
need_command nvidia-smi
need_command ss

gpu_count="$(nvidia-smi -L | wc -l | tr -d ' ')"
[[ "${gpu_count}" == "1" ]] ||
  die "Expected exactly one GPU for this single-user profile; found ${gpu_count}."

gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)"
gpu_memory_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -d ' ')"

[[ "${gpu_name}" =~ ${EXPECTED_GPU_NAME_REGEX} ]] ||
  die "GPU '${gpu_name}' does not match ${EXPECTED_GPU_NAME_REGEX}."
(( gpu_memory_mib >= MIN_GPU_MEMORY_MIB )) ||
  die "GPU reports ${gpu_memory_mib} MiB; profile requires ${MIN_GPU_MEMORY_MIB} MiB."

available_gib="$(df -BG --output=avail "${MODEL_STORE}" 2>/dev/null | awk 'NR==2 {gsub(/G/, "", $1); print $1}')"
if [[ -z "${available_gib}" ]]; then
  available_gib="$(df -BG --output=avail "$(dirname "${MODEL_STORE}")" | awk 'NR==2 {gsub(/G/, "", $1); print $1}')"
fi

(( available_gib >= MIN_RUNTIME_FREE_GIB )) ||
  die "Only ${available_gib} GiB is free; profile requires ${MIN_RUNTIME_FREE_GIB} GiB after download."

if ss -ltnH | awk -v port=":${PORT}" '$4 ~ (port "$") { found=1 } END { exit !found }'; then
  die "Port ${PORT} is already listening. Stop the existing profile or choose an approved local override."
fi

log_dir="$(profile_log_dir)"
mkdir -p -m 700 "${log_dir}"
report_file="${log_dir}/preflight-$(date -u +%Y%m%dT%H%M%SZ).txt"

{
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'profile=%s\n' "${PROFILE_NAME}"
  printf 'model=%s@%s\n' "${MODEL_ID}" "${MODEL_REVISION}"
  printf 'gpu_name=%s\n' "${gpu_name}"
  printf 'gpu_memory_mib=%s\n' "${gpu_memory_mib}"
  printf 'available_gib=%s\n' "${available_gib}"
  nvidia-smi --query-gpu=name,driver_version,power.limit,power.default_limit --format=csv,noheader,nounits
} >"${report_file}"

info "Preflight passed. Report: ${report_file}"
