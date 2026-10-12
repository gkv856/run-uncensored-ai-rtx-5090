#!/usr/bin/env bash
# Provider-neutral entry point for reviewed single-user model profiles.

set -Eeuo pipefail
umask 077

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${RUNTIME_DIR}/bin"
# shellcheck source=bin/lib.sh
source "${BIN_DIR}/lib.sh"

print_usage() {
  printf '%s\n' \
    'Usage:' \
    '  ./runtime/bootstrap.ai.sh list' \
    '  ./runtime/bootstrap.ai.sh setup <profile>' \
    '  ./runtime/bootstrap.ai.sh inspect <profile> [revision]' \
    '  ./runtime/bootstrap.ai.sh download <profile> --approve-model' \
    '  ./runtime/bootstrap.ai.sh start <profile>' \
    '  ./runtime/bootstrap.ai.sh smoke <profile>' \
    '  ./runtime/bootstrap.ai.sh benchmark <profile>' \
    '  ./runtime/bootstrap.ai.sh stop <profile>' \
    '  ./runtime/bootstrap.ai.sh deploy <profile> --approve-model' \
    '  ./runtime/bootstrap.ai.sh serve <profile> --publish-ui' \
    '  ./runtime/bootstrap.ai.sh status <profile>' \
    '  ./runtime/bootstrap.ai.sh autostart <profile> --publish-ui' \
    '  ./runtime/bootstrap.ai.sh autostart-disable' \
    '  ./runtime/bootstrap.ai.sh ui-credentials' \
    '  ./runtime/bootstrap.ai.sh ui-stop' \
    '  ./runtime/bootstrap.ai.sh serve-stop <profile>' \
    '' \
    'deploy performs setup, repository inspection, pinning, download, preflight, start, and smoke test.' \
    'The approval flag is mandatory before the script writes model files to the server disk.'
}

require_profile() {
  [[ -n "${1:-}" ]] || die "A profile name is required. Run list to see reviewed profiles."
}

require_model_approval() {
  [[ "${1:-}" == "--approve-model" ]] ||
    die "Model download is intentionally gated. Re-run with --approve-model after reviewing the inspection report."
}

install_system_packages() {
  local -a elevated=()

  if ! command -v apt-get >/dev/null 2>&1; then
    die "Automatic setup currently supports Ubuntu/Debian with apt-get. Install Python 3 venv, curl, jq, OpenSSH, and util-linux, then retry."
  fi

  if (( EUID != 0 )); then
    need_command sudo
    elevated=(sudo)
  fi

  info "Installing the Linux prerequisites required by the selected runtime."
  "${elevated[@]}" apt-get update
  "${elevated[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    iproute2 \
    jq \
    ninja-build \
    openssl \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    util-linux
}

ensure_private_runtime_env() {
  local config_dir
  local private_env
  local generated_key

  config_dir="${HOME}/.config/uncensored-ai"
  private_env="${UNCENSORED_AI_ENV_FILE:-${config_dir}/runtime.env}"
  install -d -m 700 "${config_dir}"

  if [[ ! -f "${private_env}" ]]; then
    install -m 600 "${RUNTIME_DIR}/env/runtime.env.example" "${private_env}"
    info "Created private runtime configuration: ${private_env}"
  fi

  if grep -q '^API_KEY=REPLACE_' "${private_env}"; then
    need_command openssl
    generated_key="$(openssl rand -hex 32)"
    sed -i "s/^API_KEY=.*/API_KEY=${generated_key}/" "${private_env}"
    info "Generated a private API key in ${private_env}; it was not printed."
  fi

  chmod 600 "${private_env}"
}

setup_profile() {
  local profile="$1"

  install_system_packages
  ensure_private_runtime_env
  "${BIN_DIR}/install-engine.sh" "${profile}"
}

write_inspection_report() {
  local profile="$1"
  local revision="${2:-main}"
  local log_dir
  local report_file

  load_profile "${profile}"
  log_dir="$(profile_log_dir)"
  mkdir -p -m 700 "${log_dir}"
  report_file="${log_dir}/repository-inspection-$(date -u +%Y%m%dT%H%M%SZ).txt"
  "${BIN_DIR}/inspect-model-repo.sh" "${profile}" "${revision}" >"${report_file}"
  info "Repository inspection completed: ${report_file}"
}

list_profiles() {
  local profile_file
  local profile_name
  local profile_role
  local engine
  local model_id

  printf '%-32s %-10s %-14s %s\n' 'PROFILE' 'ROLE' 'ENGINE' 'MODEL'
  for profile_file in "${TRACKED_PROFILE_DIR}"/*.env; do
    profile_name="$(awk -F= '/^PROFILE_NAME=/{print $2}' "${profile_file}")"
    profile_role="$(awk -F= '/^PROFILE_ROLE=/{print $2}' "${profile_file}")"
    engine="$(awk -F= '/^ENGINE=/{print $2}' "${profile_file}")"
    model_id="$(awk -F= '/^MODEL_ID=/{print $2}' "${profile_file}")"
    printf '%-32s %-10s %-14s %s\n' "${profile_name}" "${profile_role}" "${engine}" "${model_id}"
  done
}

command_name="${1:-help}"
profile_name="${2:-}"
option="${3:-}"

case "${command_name}" in
  help|-h|--help)
    print_usage
    ;;
  list)
    list_profiles
    ;;
  setup)
    require_profile "${profile_name}"
    setup_profile "${profile_name}"
    ;;
  inspect)
    require_profile "${profile_name}"
    write_inspection_report "${profile_name}" "${option:-main}"
    ;;
  download)
    require_profile "${profile_name}"
    require_model_approval "${option}"
    "${BIN_DIR}/pin-revision.sh" "${profile_name}" main
    "${BIN_DIR}/download-model.sh" "${profile_name}"
    ;;
  start)
    require_profile "${profile_name}"
    "${BIN_DIR}/start-profile.sh" "${profile_name}"
    ;;
  smoke)
    require_profile "${profile_name}"
    "${BIN_DIR}/smoke-test.sh" "${profile_name}"
    ;;
  benchmark)
    require_profile "${profile_name}"
    "${BIN_DIR}/benchmark-profile.sh" "${profile_name}"
    ;;
  stop)
    require_profile "${profile_name}"
    "${BIN_DIR}/stop-profile.sh" "${profile_name}"
    ;;
  deploy)
    require_profile "${profile_name}"
    require_model_approval "${option}"
    setup_profile "${profile_name}"
    write_inspection_report "${profile_name}" main
    "${BIN_DIR}/pin-revision.sh" "${profile_name}" main
    "${BIN_DIR}/download-model.sh" "${profile_name}"
    "${BIN_DIR}/start-profile.sh" "${profile_name}"
    "${BIN_DIR}/smoke-test.sh" "${profile_name}"
    ;;
  serve)
    require_profile "${profile_name}"
    "${BIN_DIR}/serve-stack.sh" "${profile_name}" "${option}"
    ;;
  status)
    require_profile "${profile_name}"
    "${BIN_DIR}/stack-status.sh" "${profile_name}"
    ;;
  autostart)
    require_profile "${profile_name}"
    "${BIN_DIR}/install-autostart.sh" "${profile_name}" "${option}"
    ;;
  autostart-disable)
    "${BIN_DIR}/remove-autostart.sh"
    ;;
  ui-credentials)
    "${BIN_DIR}/show-chat-ui-credentials.sh"
    ;;
  ui-stop)
    "${BIN_DIR}/stop-chat-ui.sh"
    ;;
  serve-stop)
    require_profile "${profile_name}"
    "${BIN_DIR}/stop-stack.sh" "${profile_name}"
    ;;
  *)
    print_usage
    die "Unknown command: ${command_name}"
    ;;
esac
