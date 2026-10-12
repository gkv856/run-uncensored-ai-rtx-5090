#!/usr/bin/env bash
# Reconcile the model and public chat UI into a known-good state.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

profile_request="${1:-}"
publish_option="${2:-}"

[[ -n "${profile_request}" ]] || die "A profile name is required."
[[ "${publish_option}" == "--publish-ui" ]] ||
  die "Stack reconciliation requires --publish-ui."

load_profile "${profile_request}"
validate_profile
require_runtime_secrets
need_command curl

model_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
  -H "Authorization: Bearer ${API_KEY}" "http://${BIND_HOST}:${PORT}/v1/models" || true)"

if [[ "${model_status}" != "200" ]]; then
  info "The private model API is not ready; reconciling ${PROFILE_NAME}."
  "${SCRIPT_DIR}/stop-profile.sh" "${PROFILE_FILE}" ||
    warn "The previous model stop sequence reported an error; continuing with a fresh start."
  "${SCRIPT_DIR}/start-profile.sh" "${PROFILE_FILE}"
else
  info "The private model API is ready."
fi

"${SCRIPT_DIR}/start-chat-ui.sh" "${PROFILE_FILE}" "--publish-ui"
"${SCRIPT_DIR}/stack-status.sh" "${PROFILE_FILE}"
info "The model API and Open WebUI are both ready."
