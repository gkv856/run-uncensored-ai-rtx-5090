#!/usr/bin/env bash
# Run three authenticated, single-user OpenAI-compatible inference checks.

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

base_url="http://${BIND_HOST}:${PORT}/v1"
log_dir="$(profile_log_dir)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
results_file="${log_dir}/benchmark-${timestamp}.jsonl"
mkdir -p -m 700 "${log_dir}"

long_context=""
for ((index = 1; index <= 96; index += 1)); do
  long_context+="A private GPU deployment should authenticate requests, bind its API to loopback, log power draw, and keep model selection configurable. "
done

run_case() {
  local label="$1"
  local prompt="$2"
  local max_tokens="$3"
  local response_file="${log_dir}/benchmark-${timestamp}-${label}.json"
  local payload
  local start_ms
  local end_ms
  local elapsed_ms
  local http_status
  local prompt_tokens
  local completion_tokens
  local tokens_per_second

  payload="$(jq -cn \
    --arg model "${SERVED_MODEL_NAME}" \
    --arg prompt "${prompt}" \
    --argjson max_tokens "${max_tokens}" \
    '{model:$model,temperature:0,max_tokens:$max_tokens,messages:[{role:"user",content:$prompt}]}')"

  start_ms="$(date +%s%3N)"
  http_status="$(curl -sS -o "${response_file}" -w '%{http_code}' \
    --connect-timeout 10 --max-time 300 \
    -H "Authorization: Bearer ${API_KEY}" \
    -H 'Content-Type: application/json' \
    -d "${payload}" "${base_url}/chat/completions")"
  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))

  [[ "${http_status}" == "200" ]] ||
    die "Benchmark '${label}' returned HTTP ${http_status}. Review ${response_file}."
  jq -e '[.choices[0].message.content, .choices[0].message.reasoning_content] | any(type == "string" and length > 0)' "${response_file}" >/dev/null ||
    die "Benchmark '${label}' returned no assistant text in either content channel. Review ${response_file}."

  prompt_tokens="$(jq -er '.usage.prompt_tokens | numbers' "${response_file}")"
  completion_tokens="$(jq -er '.usage.completion_tokens | numbers' "${response_file}")"
  tokens_per_second="$(awk -v tokens="${completion_tokens}" -v milliseconds="${elapsed_ms}" 'BEGIN { if (milliseconds <= 0) exit 1; printf "%.2f", tokens / (milliseconds / 1000) }')"

  jq -cn \
    --arg label "${label}" \
    --argjson prompt_tokens "${prompt_tokens}" \
    --argjson completion_tokens "${completion_tokens}" \
    --argjson elapsed_ms "${elapsed_ms}" \
    --argjson output_tokens_per_second "${tokens_per_second}" \
    --arg response_file "${response_file}" \
    '{label:$label,prompt_tokens:$prompt_tokens,completion_tokens:$completion_tokens,elapsed_ms:$elapsed_ms,output_tokens_per_second:$output_tokens_per_second,response_file:$response_file}' |
    tee -a "${results_file}"
}

run_case short_chat \
  'In two sentences, explain why an API token should never be embedded in a public client application.' \
  160
run_case long_context \
  "Read the following deployment notes and give a 100-word executive summary. ${long_context}" \
  256
run_case long_generation \
  'Write a practical, numbered checklist for reviewing a coding agent action before it modifies a repository.' \
  512

info "Benchmark completed. Summary records: ${results_file}"
