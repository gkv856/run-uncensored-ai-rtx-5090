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

export INSPECT_MODEL_ID="${MODEL_ID}"
export INSPECT_REVISION="${requested_revision}"
export HF_HOME="${HF_HOME:-${MODEL_STORE}/.hf-cache}"

"${python_bin}" - <<'PY'
import json
import os
from pathlib import Path

from huggingface_hub import HfApi, hf_hub_download

repo_id = os.environ["INSPECT_MODEL_ID"]
revision = os.environ["INSPECT_REVISION"]
token = os.environ.get("HF_TOKEN") or None
api = HfApi(token=token)
info = api.model_info(repo_id=repo_id, revision=revision, files_metadata=True)
files = sorted(item.rfilename for item in (info.siblings or []))
card = info.card_data.to_dict() if info.card_data is not None else {}

print(f"repository={repo_id}")
print(f"requested_revision={revision}")
print(f"resolved_revision={info.sha}")
print(f"license={card.get('license', 'not declared')}")
print("files:")
for filename in files:
    print(f"  {filename}")

python_files = [name for name in files if name.endswith(".py")]
pickle_files = [
    name
    for name in files
    if name.endswith((".bin", ".pt", ".pth", ".ckpt", ".pkl", ".pickle"))
]

try:
    config_path = hf_hub_download(
        repo_id=repo_id,
        filename="config.json",
        revision=info.sha,
        token=token,
    )
    config = json.loads(Path(config_path).read_text(encoding="utf-8"))
except Exception as exc:
    print(f"config_error={type(exc).__name__}: {exc}")
else:
    print(f"architectures={config.get('architectures')}")
    print(f"auto_map={config.get('auto_map')}")
    print(f"quantization_config_present={'quantization_config' in config}")

print(f"python_files={python_files}")
print(f"pickle_style_files={pickle_files}")
if python_files:
    print("ACTION: inspect every Python file before considering remote code.")
if pickle_files:
    print("ACTION: confirm the engine will not load pickle-style weights.")
if not python_files and not pickle_files:
    print("repository_file_risk_scan=no Python or pickle-style weight files found")
PY

