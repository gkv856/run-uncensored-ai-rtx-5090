#!/usr/bin/env bash
# Start one-second GPU power sampling for a profile and save its PID privately.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
need_command nvidia-smi

state_dir="$(profile_state_dir)"
log_dir="$(profile_log_dir)"
pid_file="${state_dir}/power.pid"
mkdir -p -m 700 "${state_dir}" "${log_dir}"

if [[ -f "${pid_file}" ]] && kill -0 "$(<"${pid_file}")" 2>/dev/null; then
  info "GPU power logger is already running: PID $(<"${pid_file}")"
  exit 0
fi

log_file="${log_dir}/gpu-power-$(date -u +%Y%m%dT%H%M%SZ).csv"
(
  printf 'timestamp_utc,name,power_draw_w,power_limit_w,temperature_c,utilization_gpu_percent,memory_used_mib\n'
  while :; do
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    metrics="$(nvidia-smi --query-gpu=name,power.draw,power.limit,temperature.gpu,utilization.gpu,memory.used --format=csv,noheader,nounits)"
    printf '%s,%s\n' "${timestamp}" "${metrics}"
    sleep 1
  done
) >>"${log_file}" 2>&1 &

logger_pid=$!
printf '%s\n' "${logger_pid}" >"${pid_file}"
printf '%s\n' "${log_file}" >"${state_dir}/power.log"
info "GPU power logging started: ${log_file}"
