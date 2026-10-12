#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile

requested_revision="${2:-}"
if [[ -z "${requested_revision}" ]]; then
  if [[ "${MODEL_REVISION}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    requested_revision="${MODEL_REVISION}"
  else
    requested_revision=main
  fi
fi

if [[ "${GATED_REPOSITORY:-0}" == "1" && -z "${HF_TOKEN}" ]]; then
  die "A read-only HF_TOKEN is required to inspect this gated repository."
fi

python_bin="$(engine_python_path)"
[[ -x "${python_bin}" ]] ||
  die "Install the pinned engine first so the Hugging Face client is available."

export REVISION_MODEL_ID="${MODEL_ID}"
export REVISION_REQUESTED="${requested_revision}"

"${python_bin}" - <<'PY'
import os
import re
from huggingface_hub import HfApi

repo_id = os.environ["REVISION_MODEL_ID"]
revision = os.environ["REVISION_REQUESTED"]
token = os.environ.get("HF_TOKEN") or None
info = HfApi(token=token).model_info(repo_id=repo_id, revision=revision)
sha = info.sha or ""
if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
    raise SystemExit(f"Hub returned a non-immutable revision: {sha!r}")
print(sha.lower())
PY

