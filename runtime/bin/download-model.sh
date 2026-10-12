#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
validate_revision
assert_engine_version

if [[ "${GATED_REPOSITORY:-0}" == "1" && -z "${HF_TOKEN}" ]]; then
  die "A read-only HF_TOKEN is required for this gated repository."
fi

install -d -m 700 "${MODEL_STORE}"
if [[ -f "${MODEL_DIR}/config.json" ]]; then
  required_free_gib="${MIN_RUNTIME_FREE_GIB:-5}"
else
  required_free_gib="${MIN_DOWNLOAD_FREE_GIB:-30}"
fi

available_kib="$(df -Pk "${MODEL_STORE}" | awk 'NR==2 {print $4}')"
required_kib=$(( required_free_gib * 1024 * 1024 ))
(( available_kib >= required_kib )) ||
  die "Only $(( available_kib / 1024 / 1024 )) GiB is free; this step requires at least ${required_free_gib} GiB."

python_bin="$(engine_python_path)"
export DOWNLOAD_MODEL_ID="${MODEL_ID}"
export DOWNLOAD_MODEL_REVISION="${MODEL_REVISION}"
export DOWNLOAD_MODEL_DIR="${MODEL_DIR}"
export HF_HOME="${HF_HOME:-${MODEL_STORE}/.hf-cache}"

info "Downloading ${MODEL_ID}@${MODEL_REVISION}"
info "Destination: ${MODEL_DIR}"

"${python_bin}" - <<'PY'
import os
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id=os.environ["DOWNLOAD_MODEL_ID"],
    revision=os.environ["DOWNLOAD_MODEL_REVISION"],
    local_dir=os.environ["DOWNLOAD_MODEL_DIR"],
    token=os.environ.get("HF_TOKEN") or None,
    ignore_patterns=["*.bin", "*.pt", "*.pth", "*.ckpt", "*.pkl", "*.pickle"],
)
PY

require_model_dir
metadata_file="${MODEL_DIR}/.uncensored-ai-source"
{
  printf 'MODEL_ID=%s\n' "${MODEL_ID}"
  printf 'MODEL_REVISION=%s\n' "${MODEL_REVISION}"
  printf 'DOWNLOADED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${metadata_file}"
chmod 600 "${metadata_file}"

actual_bytes="$(du -sb "${MODEL_DIR}" | awk '{print $1}')"
info "Download complete: ${actual_bytes} bytes at ${MODEL_DIR}"

