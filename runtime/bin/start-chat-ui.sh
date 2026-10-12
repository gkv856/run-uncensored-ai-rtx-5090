#!/usr/bin/env bash
# Start the optional, authenticated Open WebUI server stack after the private model API is ready.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

profile_request="${1:-}"
publish_option="${2:-}"

load_profile "${profile_request}"
validate_profile
require_runtime_secrets
need_command curl
need_command openssl

[[ "${publish_option}" == "--publish-ui" ]] ||
  die "Public chat UI exposure requires --publish-ui. The model API itself remains loopback-only."

model_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
  -H "Authorization: Bearer ${API_KEY}" "http://${BIND_HOST}:${PORT}/v1/models")"
[[ "${model_status}" == "200" ]] ||
  die "The selected model API is not ready on ${BIND_HOST}:${PORT}. Start the profile before starting the chat UI."

"${SCRIPT_DIR}/install-chat-ui.sh"

chat_ui_env="${HOME}/.config/uncensored-ai/chat-ui.env"
chat_ui_dir="$(dirname "${chat_ui_env}")"
compose_file="${RUNTIME_ROOT}/clients/server-openwebui/compose.yaml"
mkdir -p -m 700 "${chat_ui_dir}"
chmod 700 "${chat_ui_dir}"

if [[ -f "${chat_ui_env}" ]]; then
  normalized_chat_ui_env="$(mktemp "${chat_ui_dir}/chat-ui.env.XXXXXX")"
  # Remove both current and malformed legacy branding fields before loading
  # secrets. This makes a prior label typo unable to block a future boot.
  grep -Ev '^(\\[[:space:]]*)?CHAT_UI_(ADMIN_NAME|BRAND_NAME)=' "${chat_ui_env}" >"${normalized_chat_ui_env}"
  mv "${normalized_chat_ui_env}" "${chat_ui_env}"
  chmod 600 "${chat_ui_env}"
  set -a
  # shellcheck disable=SC1090
  source "${chat_ui_env}"
  set +a
fi

WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(openssl rand -hex 32)}"
CHAT_UI_ADMIN_PASSWORD="${CHAT_UI_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
CHAT_UI_ADMIN_EMAIL="${CHAT_UI_ADMIN_EMAIL:-owner@local}"
CHAT_UI_ADMIN_NAME="${CHAT_UI_ADMIN_NAME:-Admin}"
CHAT_UI_BRAND_NAME="${CHAT_UI_BRAND_NAME:-AI UnChained}"
OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:v0.11.3}"
CHAT_UI_BIND_HOST="${CHAT_UI_BIND_HOST:-0.0.0.0}"
CHAT_UI_PORT="${CHAT_UI_PORT:-3000}"
MODEL_API_KEY="${API_KEY}"

[[ "${CHAT_UI_BIND_HOST}" == "0.0.0.0" ]] ||
  die "Public chat UI mode requires CHAT_UI_BIND_HOST=0.0.0.0 in ${chat_ui_env}."
[[ "${CHAT_UI_PORT}" =~ ^[0-9]+$ ]] && (( CHAT_UI_PORT >= 1 && CHAT_UI_PORT <= 65535 )) ||
  die "CHAT_UI_PORT must be a valid TCP port."
[[ "${CHAT_UI_ADMIN_NAME}" != *$'\n'* && "${CHAT_UI_ADMIN_NAME}" != *"'"* ]] ||
  die "CHAT_UI_ADMIN_NAME may not contain a newline or apostrophe."
[[ "${CHAT_UI_BRAND_NAME}" != *$'\n'* && "${CHAT_UI_BRAND_NAME}" != *"'"* ]] ||
  die "CHAT_UI_BRAND_NAME may not contain a newline or apostrophe."

printf '%s\n' \
  "WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}" \
  "CHAT_UI_ADMIN_PASSWORD=${CHAT_UI_ADMIN_PASSWORD}" \
  "CHAT_UI_ADMIN_EMAIL=${CHAT_UI_ADMIN_EMAIL}" \
  "CHAT_UI_ADMIN_NAME='${CHAT_UI_ADMIN_NAME}'" \
  "CHAT_UI_BRAND_NAME='${CHAT_UI_BRAND_NAME}'" \
  "OPEN_WEBUI_IMAGE=${OPEN_WEBUI_IMAGE}" \
  "CHAT_UI_BIND_HOST=${CHAT_UI_BIND_HOST}" \
  "CHAT_UI_PORT=${CHAT_UI_PORT}" \
  "MODEL_API_KEY=${MODEL_API_KEY}" >"${chat_ui_env}"
chmod 600 "${chat_ui_env}"

docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  need_command sudo
  docker_cmd=(sudo docker)
fi

"${docker_cmd[@]}" compose --env-file "${chat_ui_env}" -f "${compose_file}" up -d --remove-orphans
"${SCRIPT_DIR}/configure-chat-ui-branding.sh"
ui_deadline=$((SECONDS + 180))
until ui_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 \
  "http://127.0.0.1:${CHAT_UI_PORT}/" || true)" && [[ "${ui_status}" =~ ^(200|302|303|307|308)$ ]]; do
  if (( SECONDS >= ui_deadline )); then
    warn "Open WebUI did not become reachable within 180 seconds. Inspect redacted container logs with: ${docker_cmd[*]} logs uncensored-ai-server-openwebui"
    exit 1
  fi
  sleep 2
done

info "Authenticated chat UI is ready at http://<SERVER_PUBLIC_IP>:${CHAT_UI_PORT}."
warn "This raw-IP endpoint is HTTP only. Use a domain with HTTPS or a private overlay before sending sensitive material."
warn "Read the initial Open WebUI credentials with: ./runtime/bootstrap.ai.sh ui-credentials"
