#!/usr/bin/env bash
# Print the locally stored Open WebUI administrator credential only in the operator's SSH terminal.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

chat_ui_env="${HOME}/.config/uncensored-ai/chat-ui.env"
[[ -f "${chat_ui_env}" ]] || die "No server-hosted chat UI configuration exists: ${chat_ui_env}"

set -a
# shellcheck disable=SC1090
source "${chat_ui_env}"
set +a

printf '%s\n' \
  'Open WebUI administrator credentials (do not copy into chat, screenshots, or Git):' \
  "Email: ${CHAT_UI_ADMIN_EMAIL}" \
  "Password: ${CHAT_UI_ADMIN_PASSWORD}"
