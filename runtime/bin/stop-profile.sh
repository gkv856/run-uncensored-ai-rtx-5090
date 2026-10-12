#!/usr/bin/env bash
# Stop a profile's server process group, supervisor, and power logger cleanly.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
state_dir="$(profile_state_dir)"
server_pid_file="${state_dir}/server.pid"
supervisor_pid_file="${state_dir}/supervisor.pid"
stop_request_file="${state_dir}/stop.request"

mkdir -p -m 700 "${state_dir}"
touch "${stop_request_file}"

if [[ -f "${server_pid_file}" ]]; then
  server_pid="$(<"${server_pid_file}")"
  [[ "${server_pid}" =~ ^[0-9]+$ ]] || die "Invalid server PID file: ${server_pid_file}"
  if kill -0 "${server_pid}" 2>/dev/null; then
    kill -- "-${server_pid}" 2>/dev/null || kill "${server_pid}"
    info "Server termination requested: process group ${server_pid}"
  fi
fi

if [[ -f "${supervisor_pid_file}" ]]; then
  supervisor_pid="$(<"${supervisor_pid_file}")"
  [[ "${supervisor_pid}" =~ ^[0-9]+$ ]] || die "Invalid supervisor PID file: ${supervisor_pid_file}"
  if kill -0 "${supervisor_pid}" 2>/dev/null; then
    kill "${supervisor_pid}"
    info "Supervisor termination requested: PID ${supervisor_pid}"
  fi
fi

"${SCRIPT_DIR}/stop-power-log.sh" "${PROFILE_FILE}"
rm -f "${server_pid_file}" "${supervisor_pid_file}"
info "Stop sequence completed for ${PROFILE_NAME}."
