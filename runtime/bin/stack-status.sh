#!/usr/bin/env bash
# Report whether the private model API and the server-hosted Open WebUI are usable.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

profile_request="${1:-}"

load_profile "${profile_request}"
validate_profile
require_runtime_secrets
need_command curl

model_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
  -H "Authorization: Bearer ${API_KEY}" "http://${BIND_HOST}:${PORT}/v1/models" || true)"

chat_ui_env="${HOME}/.config/uncensored-ai/chat-ui.env"
ui_status="missing"
container_status="missing"

if [[ -f "${chat_ui_env}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${chat_ui_env}"
  set +a

  CHAT_UI_PORT="${CHAT_UI_PORT:-3000}"
  ui_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
    "http://127.0.0.1:${CHAT_UI_PORT}/" || true)"

  if command -v docker >/dev/null 2>&1; then
    docker_cmd=(docker)
    if ! docker info >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
      docker_cmd=(sudo docker)
    fi
    container_status="$("${docker_cmd[@]}" inspect -f '{{.State.Running}}' uncensored-ai-server-openwebui 2>/dev/null || true)"
  fi
fi

printf 'model_api=%s\nopen_webui=%s\nopen_webui_container=%s\n' \
  "${model_status:-unreachable}" "${ui_status:-unreachable}" "${container_status:-unreachable}"

[[ "${model_status}" == "200" ]] || exit 1
[[ "${ui_status}" =~ ^(200|302|303|307|308)$ ]] || exit 1
[[ "${container_status}" == "true" ]] || exit 1
