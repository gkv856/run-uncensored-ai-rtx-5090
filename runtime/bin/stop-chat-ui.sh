#!/usr/bin/env bash
# Stop the optional Open WebUI stack while retaining its named volume and administrator account.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

chat_ui_env="${HOME}/.config/uncensored-ai/chat-ui.env"
compose_file="${RUNTIME_ROOT}/clients/server-openwebui/compose.yaml"

[[ -f "${chat_ui_env}" ]] || die "No server-hosted chat UI configuration exists: ${chat_ui_env}"
need_command docker

docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  need_command sudo
  docker_cmd=(sudo docker)
fi

"${docker_cmd[@]}" compose --env-file "${chat_ui_env}" -f "${compose_file}" down
info "Server-hosted chat UI stopped. Its named volume and credentials were retained."
