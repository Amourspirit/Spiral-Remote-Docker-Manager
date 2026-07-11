#!/usr/bin/env bash
# tunnel_route.sh — enable/disable Cloudflare DNS record for tunnel routing.

set -euo pipefail

declare -a RECORD_LIST=()
declare -a CREATED_ROUTE_IDS=()

# if [[ -f ~/Documents/Projects/Obsidian/tmp/.env_tr ]]; then
#   source ~/Documents/Projects/Obsidian/tmp/.env_tr
# fi

# Delimiters: ; , \n (newline) or space.
# Works with both bash and zsh.

list_parse() {
    local input="$1"
    local IFS_old=$IFS

    # Replace ; , \n with tab, collapse whitespace runs to single tab
    local cleaned
    cleaned=$(
        printf '%s' "$input" \
        | tr ';,' '\t\t' \
        | tr '\n' '\t' \
        | tr -s '\t[:space:]' '\t' \
        | sed 's/^\t//;s/\t$//'
    )

    # Read into array (works in both bash and zsh)
    local arr=()
    while IFS=$IFS_old read -r -d $'\t' item || [[ -n "$item" ]]; do
        [[ -n "$item" ]] && arr+=("$item")
    done <<< "$cleaned"

    echo "${arr[@]}"
}

log() {
  echo "[tunnel_route] $*" >&2
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

api_request() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"
  local connect_timeout="${CF_CONNECT_TIMEOUT:-5}"
  local max_time="${CF_MAX_TIME:-20}"
  local retry_count="${CF_RETRY_COUNT:-2}"

  if [ -n "$payload" ]; then
    curl --silent --show-error --fail \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      --retry "$retry_count" \
      --retry-delay 1 \
      --retry-all-errors \
      -X "$method" "$url" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$payload"
  else
    curl --silent --show-error --fail \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      --retry "$retry_count" \
      --retry-delay 1 \
      --retry-all-errors \
      -X "$method" "$url" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json"
  fi
}

assert_cf_success() {
  local response="$1"
  local operation="$2"
  if [ "$(printf '%s' "$response" | jq -r '.success // false')" != "true" ]; then
    echo "Cloudflare API ${operation} failed: $(printf '%s' "$response" | jq -c '.errors // []')" >&2
    return 1
  fi
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_valid_record_name() {
  local record_name="$1"
  [[ "$record_name" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]
}

parse_record_names() {
  local raw="${RECORD_NAMES:-}"
  local lowered
  local name
  local trimmed
  local existing
  local duplicate
  local -a deduped=()
  local names
  local deduped_count=0

  if [ -z "$raw" ]; then
    echo "RECORD_NAMES is empty" >&2
    return 1
  fi
  names=($(list_parse "$raw"))

  for name in "${names[@]}"; do
    trimmed="$(trim_value "$name")"
    [ -z "$trimmed" ] && continue

    lowered="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
    if ! is_valid_record_name "$lowered"; then
      echo "Invalid DNS record name in RECORD_NAMES: $trimmed" >&2
      return 1
    fi

    duplicate=0
    if [ "$deduped_count" -gt 0 ]; then
      set +u
      for existing in "${deduped[@]}"; do
        if [ "$existing" = "$lowered" ]; then
          duplicate=1
          break
        fi
      done
      set -u
    fi

    if [ "$duplicate" -eq 0 ]; then
      deduped+=("$lowered")
      deduped_count=$((deduped_count + 1))
    fi
  done

  set +u
  RECORD_LIST=("${deduped[@]}")
  set -u

  if [ "${#RECORD_LIST[@]}" -eq 0 ]; then
    echo "RECORD_NAMES did not contain any valid DNS record names" >&2
    return 1
  fi

  log "Resolved ${#RECORD_LIST[@]} record(s) from RECORD_NAMES"
}

get_record_id() {
  local record_name="$1"
  local response
  response="$(api_request GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=CNAME&name=${record_name}")" || return 1
  assert_cf_success "$response" "lookup" || return 1
  printf '%s' "$response" | jq -r '.result[0].id // empty'
}

enable_route_for_record() {
  local record_name="$1"
  local record_id
  record_id="$(get_record_id "$record_name")" || return 1

  if [ -z "$record_id" ]; then
    local payload
    local response
    payload="$(jq -n --arg name "$record_name" --arg content "$TUNNEL_CNAME" '{type:"CNAME",name:$name,content:$content,proxied:true}')"
    response="$(api_request POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" "$payload")" || return 1
    assert_cf_success "$response" "create" || return 1
    record_id="$(printf '%s' "$response" | jq -r '.result.id // empty')"
    if [ -z "$record_id" ]; then
      echo "Cloudflare API create returned no record id for ${record_name}" >&2
      return 1
    fi
    log "Route enabled: ${record_name} -> ${TUNNEL_CNAME}"
    printf '%s' "$record_id"
  else
    log "Route already exists: ${record_name}"
    printf '%s' ""
  fi
}

disable_route_for_record() {
  local record_name="$1"
  local zone_id="$2"
  local record_id
  record_id="$(get_record_id "$record_name")" || return 1

  if [ -n "$record_id" ]; then
    local response
    response="$(api_request DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}")" || return 1
    assert_cf_success "$response" "delete" || return 1
    log "Route disabled: ${record_name}"
  else
    log "Route already removed: ${record_name}"
  fi
}

rollback_created_routes() {
  local zone_id="$1"
  local created_id
  local response
  local status=0

  if [ "${#CREATED_ROUTE_IDS[@]}" -eq 0 ]; then
    return
  fi

  log "Rolling back ${#CREATED_ROUTE_IDS[@]} newly created route(s)"
  for created_id in "${CREATED_ROUTE_IDS[@]}"; do
    response="$(api_request DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${created_id}")" || status=1
    if [ "$status" -eq 0 ]; then
      if ! assert_cf_success "$response" "rollback-delete"; then
        status=1
      fi
    fi
  done

  return "$status"
}

enable_route_atomic() {
  local created_id
  local record_name
  local zone_id="${ZONE_ID:-}"
  CREATED_ROUTE_IDS=()

  for record_name in "${RECORD_LIST[@]}"; do
    if ! created_id="$(enable_route_for_record "$record_name")"; then
      rollback_created_routes "$zone_id"
      echo "Failed to enable route for ${record_name}; rollback complete" >&2
      return 1
    fi

    if [ -n "$created_id" ]; then
      CREATED_ROUTE_IDS+=("$created_id")
    fi
  done
}

disable_route() {
  local record_name
  local zone_id="${ZONE_ID:-}"
  local status=0
  for record_name in "${RECORD_LIST[@]}"; do
    if ! disable_route_for_record "$record_name" "$zone_id"; then
      status=1
    fi
  done
  return "$status"
}

main() {
  require_env ZONE_ID
  require_env API_TOKEN
  require_env RECORD_NAMES
  parse_record_names || return 1

  if [ -z "${TUNNEL_CNAME:-}" ] && [ -n "${CF_TUNNEL_ID:-}" ]; then
    TUNNEL_CNAME="${CF_TUNNEL_ID}.cfargotunnel.com"
  fi

  require_env TUNNEL_CNAME

  case "${1:-}" in
    enable)
      enable_route_atomic
      ;;
    disable)
      disable_route
      ;;
    rid)
      if [ "${#RECORD_LIST[@]}" -eq 0 ]; then
        return 0
      fi
      get_record_id "${RECORD_LIST[0]}"
      ;;
    *)
      echo "Usage: $0 {enable|disable|rid}" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "${1:-}"
fi
