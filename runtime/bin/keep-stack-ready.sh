#!/usr/bin/env bash
# Keep the selected profile and server-hosted UI available after VM or process restarts.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

profile_request="${1:-}"
publish_option="${2:-}"

[[ -n "${profile_request}" ]] || die "A profile name is required."
[[ "${publish_option}" == "--publish-ui" ]] ||
  die "The boot guardian requires --publish-ui."

READY_RECONCILE_INTERVAL_SECONDS="${READY_RECONCILE_INTERVAL_SECONDS:-30}"
[[ "${READY_RECONCILE_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] && (( READY_RECONCILE_INTERVAL_SECONDS >= 5 )) ||
  die "READY_RECONCILE_INTERVAL_SECONDS must be an integer of at least 5."

trap 'exit 0' INT TERM

while :; do
  if "${SCRIPT_DIR}/stack-status.sh" "${profile_request}" >/dev/null 2>&1; then
    sleep "${READY_RECONCILE_INTERVAL_SECONDS}"
    continue
  fi

  warn "The AI stack is not ready; starting a recovery cycle."
  if ! "${SCRIPT_DIR}/ensure-stack-ready.sh" "${profile_request}" "${publish_option}"; then
    warn "Recovery did not complete; retrying after ${READY_RECONCILE_INTERVAL_SECONDS} seconds."
  fi
  sleep "${READY_RECONCILE_INTERVAL_SECONDS}"
done
