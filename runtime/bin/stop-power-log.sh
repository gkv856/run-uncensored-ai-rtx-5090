#!/usr/bin/env bash
# Stop the one-second GPU power logger for a profile if it is running.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
state_dir="$(profile_state_dir)"
pid_file="${state_dir}/power.pid"

if [[ ! -f "${pid_file}" ]]; then
  info "No GPU power logger PID file exists for ${PROFILE_NAME}."
  exit 0
fi

logger_pid="$(<"${pid_file}")"
[[ "${logger_pid}" =~ ^[0-9]+$ ]] || die "Invalid GPU power logger PID file: ${pid_file}"

if kill -0 "${logger_pid}" 2>/dev/null; then
  kill "${logger_pid}"
  info "GPU power logger stopped: PID ${logger_pid}"
fi

rm -f "${pid_file}"
