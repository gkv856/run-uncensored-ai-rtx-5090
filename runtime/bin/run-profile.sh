#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"

case "${ENGINE}" in
  sglang)
    exec "${SCRIPT_DIR}/launch-sglang.sh" "${PROFILE_FILE}"
    ;;
  vllm)
    exec "${SCRIPT_DIR}/launch-vllm.sh" "${PROFILE_FILE}"
    ;;
  *)
    die "Unsupported engine: ${ENGINE}"
    ;;
esac

