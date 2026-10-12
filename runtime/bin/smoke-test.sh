#!/usr/bin/env bash
# Verify authentication and the OpenAI-compatible chat and tool-call routes for one profile.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
require_runtime_secrets
need_command curl
need_command jq

state_dir="$(profile_state_dir)"
log_dir="$(profile_log_dir)"
mkdir -p -m 700 "${state_dir}" "${log_dir}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
base_url="http://${BIND_HOST}:${PORT}/v1"
anonymous_output="${state_dir}/anonymous-${timestamp}.json"
wrong_key_output="${state_dir}/wrong-key-${timestamp}.json"
authorized_output="${state_dir}/authorized-${timestamp}.json"
chat_output="${log_dir}/smoke-chat-${timestamp}.json"
tool_output="${log_dir}/smoke-tool-${timestamp}.json"

anonymous_status="$(curl -sS -o "${anonymous_output}" -w '%{http_code}' --connect-timeout 5 --max-time 15 "${base_url}/models")"
case "${anonymous_status}" in
  401|403) ;;
  *) die "Unauthenticated /v1/models returned HTTP ${anonymous_status}; endpoint is not acceptably private." ;;
esac

wrong_key_status="$(curl -sS -o "${wrong_key_output}" -w '%{http_code}' --connect-timeout 5 --max-time 15 -H 'Authorization: Bearer not-the-api-key' "${base_url}/models")"
case "${wrong_key_status}" in
  401|403) ;;
  *) die "Incorrect-key /v1/models returned HTTP ${wrong_key_status}; endpoint is not acceptably private." ;;
esac

authorized_status="$(curl -sS -o "${authorized_output}" -w '%{http_code}' --connect-timeout 5 --max-time 15 -H "Authorization: Bearer ${API_KEY}" "${base_url}/models")"
[[ "${authorized_status}" == "200" ]] ||
  die "Authenticated /v1/models returned HTTP ${authorized_status}."
jq -e --arg model "${SERVED_MODEL_NAME}" '.data[]?.id == $model' "${authorized_output}" >/dev/null ||
  die "The expected served model alias '${SERVED_MODEL_NAME}' is absent from /v1/models."

chat_payload="$(jq -cn --arg model "${SERVED_MODEL_NAME}" '{model:$model,temperature:0,max_tokens:24,messages:[{role:"user",content:"Reply with exactly: ready"}]}')"
chat_status="$(curl -sS -o "${chat_output}" -w '%{http_code}' --connect-timeout 10 --max-time 120 -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' -d "${chat_payload}" "${base_url}/chat/completions")"
[[ "${chat_status}" == "200" ]] ||
  die "Chat completion returned HTTP ${chat_status}. Review ${chat_output}."
jq -e '.choices[0].message.content | strings | length > 0' "${chat_output}" >/dev/null ||
  die "Chat completion returned no assistant content. Review ${chat_output}."

tool_payload="$(jq -cn --arg model "${SERVED_MODEL_NAME}" '{model:$model,temperature:0,max_tokens:64,messages:[{role:"user",content:"Call echo_text with value ready."}],tools:[{type:"function",function:{name:"echo_text",description:"Return the supplied text.",parameters:{type:"object",properties:{value:{type:"string"}},required:["value"],additionalProperties:false}}}],tool_choice:"auto"}')"
tool_status="$(curl -sS -o "${tool_output}" -w '%{http_code}' --connect-timeout 10 --max-time 120 -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' -d "${tool_payload}" "${base_url}/chat/completions")"
[[ "${tool_status}" == "200" ]] ||
  die "Tool-call request returned HTTP ${tool_status}. Review ${tool_output}."
jq -e '.choices[0].message | (.content | type == "string") or (.tool_calls | type == "array")' "${tool_output}" >/dev/null ||
  die "Tool-call request produced an invalid response shape. Review ${tool_output}."

info "Smoke test passed. Results: ${chat_output}, ${tool_output}"
