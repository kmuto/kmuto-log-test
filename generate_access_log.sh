#!/usr/bin/env bash
set -euo pipefail
LANG=C
export LANG

OUTPUT_FILE="${1:-./access.log}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"
INTERVAL_JITTER_RATIO="${INTERVAL_JITTER_RATIO:-0.20}"
LOG_FORMAT="${LOG_FORMAT:-combined}"

if [[ "${LOG_FORMAT}" != "combined" && "${LOG_FORMAT}" != "jsonl" ]]; then
  echo "Invalid LOG_FORMAT: ${LOG_FORMAT}" >&2
  echo "Use LOG_FORMAT=combined or LOG_FORMAT=jsonl" >&2
  exit 1
fi

METHODS=("GET" "POST")
VERSIONS=("HTTP/1.1" "HTTP/2.0")
USER_AGENTS=(
  "ExampleAppClient/1.0 (+https://example.invalid/client)"
  "InternalMonitor/0.3 (env=staging; team=platform)"
  "LoadTestRunner/2.1"
  "SyntheticBrowser/99.0"
  "sqlmap/1.8.1"
  "Nmap Scripting Engine"
  "curl/8.7.1"
  "Mozilla/5.0 zgrab/0.x"
)

NORMAL_PATHS=(
  "/api/v1/health/"
  "/api/v1/users"
  "/api/v1/users/42/"
  "/api/v1/orders?status=pending&limit=20"
  "/api/v1/orders/ord_123456/items"
  "/api/v1/search?q=demo+item&page=2"
  "/api/v1/reports/daily-summary"
  "/api/v1/auth/token"
)
ATTACK_PATHS=(
  "/wp-login.php"
  "/phpmyadmin/"
  "/.env"
  "/admin"
  "/api/v1/users?id=1%20OR%201=1"
  "/search?q=%27%20OR%20%271%27=%271"
  "/download?file=../../../../etc/passwd"
  "/api/v1/upload?name=<script>alert(1)</script>"
  "/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh"
)

echo "Writing nginx-style access logs to: ${OUTPUT_FILE}"
echo "Interval: ${INTERVAL_SECONDS}s, jitter ratio: ±${INTERVAL_JITTER_RATIO} (Ctrl+C to stop)"
echo "Log format: ${LOG_FORMAT} (combined|jsonl)"
echo "Traffic mix: normal ~75%, attack-like ~25%"

json_escape() {
  local s="${1}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

while true; do
  case $((RANDOM % 3)) in
    0) ip="192.0.2.$((RANDOM % 254 + 1))" ;;
    1) ip="198.51.100.$((RANDOM % 254 + 1))" ;;
    *) ip="203.0.113.$((RANDOM % 254 + 1))" ;;
  esac
  if (( RANDOM % 100 < 75 )); then
    path="${NORMAL_PATHS[RANDOM % ${#NORMAL_PATHS[@]}]}"
  else
    path="${ATTACK_PATHS[RANDOM % ${#ATTACK_PATHS[@]}]}"
  fi

  case "${path}" in
    "/api/v1/health/")
      method="GET"
      status_pool=(200 200 200 200 503)
      ;;
    "/api/v1/auth/token")
      method="${METHODS[RANDOM % ${#METHODS[@]}]}"
      status_pool=(200 200 401 401 429)
      ;;
    "/api/v1/users"|"/api/v1/users/42/"|"/api/v1/orders?status=pending&limit=20"|"/api/v1/orders/ord_123456/items"|"/api/v1/search?q=demo+item&page=2"|"/api/v1/reports/daily-summary")
      method="${METHODS[RANDOM % ${#METHODS[@]}]}"
      status_pool=(200 200 200 301 404 500)
      ;;
    "/wp-login.php"|"/phpmyadmin/"|"/.env"|"/admin"|"/api/v1/users?id=1%20OR%201=1"|"/search?q=%27%20OR%20%271%27=%271"|"/download?file=../../../../etc/passwd"|"/api/v1/upload?name=<script>alert(1)</script>"|"/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh")
      method="GET"
      status_pool=(401 403 403 404 404 429 500)
      ;;
    *)
      method="${METHODS[RANDOM % ${#METHODS[@]}]}"
      status_pool=(200 404 500)
      ;;
  esac

  status="${status_pool[RANDOM % ${#status_pool[@]}]}"
  version="${VERSIONS[RANDOM % ${#VERSIONS[@]}]}"
  ua="${USER_AGENTS[RANDOM % ${#USER_AGENTS[@]}]}"
  bytes=$((RANDOM % 20000))
  ts="$(date '+%d/%b/%Y:%H:%M:%S %z')"

  if [[ "${LOG_FORMAT}" == "jsonl" ]]; then
    request="${method} ${path} ${version}"
    printf '{"time_local":"%s","remote_addr":"%s","request":"%s","request_method":"%s","request_uri":"%s","server_protocol":"%s","status":%d,"body_bytes_sent":%d,"http_referer":"-","http_user_agent":"%s"}\n' \
      "$(json_escape "${ts}")" \
      "$(json_escape "${ip}")" \
      "$(json_escape "${request}")" \
      "$(json_escape "${method}")" \
      "$(json_escape "${path}")" \
      "$(json_escape "${version}")" \
      "${status}" \
      "${bytes}" \
      "$(json_escape "${ua}")" >> "${OUTPUT_FILE}"
  else
    printf '%s - - [%s] "%s %s %s" %d %d "-" "%s"\n' \
      "${ip}" "${ts}" "${method}" "${path}" "${version}" "${status}" "${bytes}" "${ua}" >> "${OUTPUT_FILE}"
  fi

  sleep_seconds="$(
    awk -v base="${INTERVAL_SECONDS}" -v jitter="${INTERVAL_JITTER_RATIO}" -v randv="${RANDOM}" 'BEGIN {
      offset = ((randv / 32767.0) * 2.0) - 1.0
      v = base * (1.0 + jitter * offset)
      if (v < 0.001) v = 0.001
      printf "%.3f", v
    }'
  )"

  sleep "${sleep_seconds}"
done
