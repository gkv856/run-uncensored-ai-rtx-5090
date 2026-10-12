#!/usr/bin/env bash
# Install a system service that restores the selected model and UI after every VM boot.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

profile_request="${1:-}"
publish_option="${2:-}"

[[ -n "${profile_request}" ]] || die "A profile name is required."
[[ "${publish_option}" == "--publish-ui" ]] ||
  die "Automatic startup requires --publish-ui."
need_command systemctl

load_profile "${profile_request}"
validate_profile
require_runtime_secrets

service_user="$(id -un)"
service_group="$(id -gn)"
service_home="${HOME}"
project_root="$(cd "${RUNTIME_ROOT}/.." && pwd)"
template_file="${RUNTIME_ROOT}/systemd/uncensored-ai-stack.service.template"
service_file="/etc/systemd/system/uncensored-ai-stack.service"
rendered_unit="$(mktemp)"

cleanup() {
  rm -f "${rendered_unit}"
}
trap cleanup EXIT

[[ -f "${template_file}" ]] || die "Missing systemd service template: ${template_file}"

# Ensure Docker and its group are present before systemd starts the guardian.
"${SCRIPT_DIR}/install-chat-ui.sh"
getent group docker >/dev/null || die "Docker installed without a docker group."

sed \
  -e "s|@SERVICE_USER@|${service_user}|g" \
  -e "s|@SERVICE_GROUP@|${service_group}|g" \
  -e "s|@SERVICE_HOME@|${service_home}|g" \
  -e "s|@PROJECT_ROOT@|${project_root}|g" \
  -e "s|@RUNTIME_ROOT@|${RUNTIME_ROOT}|g" \
  -e "s|@PROFILE_NAME@|${PROFILE_NAME}|g" \
  "${template_file}" >"${rendered_unit}"

elevated=()
if (( EUID != 0 )); then
  need_command sudo
  elevated=(sudo)
fi

"${elevated[@]}" install -o root -g root -m 644 "${rendered_unit}" "${service_file}"
"${elevated[@]}" systemctl daemon-reload
"${elevated[@]}" systemctl enable --now uncensored-ai-stack.service

ready_deadline=$((SECONDS + ${AUTOSTART_READY_TIMEOUT_SECONDS:-1200}))
until "${SCRIPT_DIR}/stack-status.sh" "${PROFILE_FILE}" >/dev/null; do
  if (( SECONDS >= ready_deadline )); then
    die "Automatic startup is enabled, but the stack did not become ready before the timeout. Run status and inspect the system service journal."
  fi
  sleep 5
done

info "Automatic startup is enabled and both services are ready."
