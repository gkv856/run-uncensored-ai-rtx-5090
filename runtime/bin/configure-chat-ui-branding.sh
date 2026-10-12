#!/usr/bin/env bash
# Keep the existing Open WebUI administrator's visible name aligned with the server UI brand.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

chat_ui_env="${HOME}/.config/uncensored-ai/chat-ui.env"
[[ -f "${chat_ui_env}" ]] || die "No server-hosted chat UI configuration exists: ${chat_ui_env}"

set -a
# shellcheck disable=SC1090
source "${chat_ui_env}"
set +a

: "${CHAT_UI_ADMIN_NAME:?CHAT_UI_ADMIN_NAME is missing from ${chat_ui_env}}"
[[ "${CHAT_UI_ADMIN_NAME}" != *$'\n'* ]] || die "CHAT_UI_ADMIN_NAME may not contain a newline."

need_command docker
docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  need_command sudo
  docker_cmd=(sudo docker)
fi

for attempt in $(seq 1 30); do
  if "${docker_cmd[@]}" exec \
    -e CHAT_UI_ADMIN_NAME \
    uncensored-ai-server-openwebui \
    python3 - <<'PY'
import os
import sqlite3
import time

db = sqlite3.connect("/app/backend/data/webui.db", timeout=10)
db.execute("PRAGMA busy_timeout = 10000")
try:
    admin_count = db.execute("SELECT count(*) FROM user WHERE role = 'admin'").fetchone()[0]
    if admin_count != 1:
        raise SystemExit(75)
    result = db.execute(
        "UPDATE user SET name = ?, updated_at = ? WHERE role = 'admin'",
        (os.environ["CHAT_UI_ADMIN_NAME"], int(time.time())),
    )
    db.commit()
finally:
    db.close()

if result.rowcount != 1:
    raise SystemExit(75)
PY
  then
    info "Open WebUI administrator display name reconciled."
    exit 0
  fi
  (( attempt == 30 )) || sleep 1
done

die "Open WebUI did not create the configured administrator in time."
