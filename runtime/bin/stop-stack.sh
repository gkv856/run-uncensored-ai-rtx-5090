#!/usr/bin/env bash
# Stop the public chat UI first, then stop the selected model profile and GPU power logger.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ui_exit=0
if [[ -f "${HOME}/.config/uncensored-ai/chat-ui.env" ]]; then
  if "${SCRIPT_DIR}/stop-chat-ui.sh"; then
    :
  else
    ui_exit=$?
    warn "The UI stop operation failed, but the model stop operation will still continue."
  fi
else
  info "No server-hosted chat UI configuration exists; stopping the model profile only."
fi

"${SCRIPT_DIR}/stop-profile.sh" "${1:-}"
exit "${ui_exit}"
