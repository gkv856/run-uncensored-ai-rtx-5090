#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile

requested_revision="${2:-main}"
resolved_sha="$("${SCRIPT_DIR}/resolve-revision.sh" "${PROFILE_FILE}" "${requested_revision}")"
[[ "${resolved_sha}" =~ ^[0-9a-f]{40}$ ]] ||
  die "Revision resolver returned an invalid SHA."

install -d -m 700 "${PROFILE_OVERRIDE_DIR}"
revision_file="${PROFILE_OVERRIDE_DIR}/${PROFILE_NAME}.revision.env"
temporary_file="$(mktemp "${PROFILE_OVERRIDE_DIR}/.${PROFILE_NAME}.revision.XXXXXX")"
trap 'rm -f "${temporary_file}"' EXIT

printf 'MODEL_REVISION=%s\n' "${resolved_sha}" > "${temporary_file}"
chmod 600 "${temporary_file}"
mv -f "${temporary_file}" "${revision_file}"
trap - EXIT

info "Pinned ${MODEL_ID} to ${resolved_sha}"
info "Local revision override: ${revision_file}"

