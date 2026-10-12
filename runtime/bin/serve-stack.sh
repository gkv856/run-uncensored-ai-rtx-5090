#!/usr/bin/env bash
# Start a reviewed model profile and its optional public chat UI as one explicit operator action.

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

[[ "${publish_option}" == "--publish-ui" ]] ||
  die "Starting the public chat UI requires --publish-ui."

"${SCRIPT_DIR}/ensure-stack-ready.sh" "${PROFILE_FILE}" "--publish-ui"
