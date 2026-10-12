#!/usr/bin/env bash
# Start one reviewed profile, its bounded supervisor, and GPU power logging.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
need_command curl
need_command setsid

state_dir="$(profile_state_dir)"
log_dir="$(profile_log_dir)"
supervisor_pid_file="${state_dir}/supervisor.pid"
server_pid_file="${state_dir}/server.pid"
stop_request_file="${state_dir}/stop.request"
server_log="${log_dir}/server-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p -m 700 "${state_dir}" "${log_dir}"

if [[ -f "${supervisor_pid_file}" ]]; then
  existing_supervisor_pid="$(<"${supervisor_pid_file}")"
  [[ "${existing_supervisor_pid}" =~ ^[0-9]+$ ]] ||
    die "Invalid supervisor PID file: ${supervisor_pid_file}"
  if kill -0 "${existing_supervisor_pid}" 2>/dev/null; then
    die "Profile ${PROFILE_NAME} is already running under supervisor PID ${existing_supervisor_pid}."
  fi
  warn "Removing stale supervisor PID file: ${supervisor_pid_file}"
  rm -f "${supervisor_pid_file}"
fi

rm -f "${stop_request_file}" "${server_pid_file}"
"${SCRIPT_DIR}/preflight.sh" "${PROFILE_FILE}"
"${SCRIPT_DIR}/start-power-log.sh" "${PROFILE_FILE}"

supervise_server() {
  local attempts=0
  local exit_status=0

  while :; do
    setsid "${SCRIPT_DIR}/run-profile.sh" "${PROFILE_FILE}" >>"${server_log}" 2>&1 &
    server_pid=$!
    printf '%s\n' "${server_pid}" >"${server_pid_file}"

    if wait "${server_pid}"; then
      exit_status=0
    else
      exit_status=$?
    fi

    rm -f "${server_pid_file}"
    [[ ! -f "${stop_request_file}" ]] || exit 0

    attempts=$((attempts + 1))
    if (( attempts > SUPERVISOR_MAX_RESTARTS )); then
      printf '[error] Server exited with status %s after %s restart attempts.\n' "${exit_status}" "${SUPERVISOR_MAX_RESTARTS}" >>"${server_log}"
      exit "${exit_status}"
    fi

    printf '[warn] Server exited with status %s; restarting attempt %s of %s.\n' "${exit_status}" "${attempts}" "${SUPERVISOR_MAX_RESTARTS}" >>"${server_log}"
    sleep "${SUPERVISOR_RESTART_DELAY_SECONDS}"
  done
}

supervise_server &
supervisor_pid=$!
printf '%s\n' "${supervisor_pid}" >"${supervisor_pid_file}"
printf '%s\n' "${server_log}" >"${state_dir}/server.log"

deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS))
until curl -fsS --connect-timeout 2 --max-time 5 -H "Authorization: Bearer ${API_KEY}" "http://${BIND_HOST}:${PORT}/v1/models" >/dev/null; do
  if ! kill -0 "${supervisor_pid}" 2>/dev/null; then
    warn "Server supervisor exited before the API became ready. See ${server_log}"
    "${SCRIPT_DIR}/stop-power-log.sh" "${PROFILE_FILE}"
    rm -f "${supervisor_pid_file}" "${server_pid_file}"
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    warn "Server did not become ready within ${STARTUP_TIMEOUT_SECONDS} seconds. See ${server_log}"
    "${SCRIPT_DIR}/stop-profile.sh" "${PROFILE_FILE}"
    exit 1
  fi
  sleep 2
done

info "Profile is ready at http://${BIND_HOST}:${PORT}/v1. Server log: ${server_log}"
