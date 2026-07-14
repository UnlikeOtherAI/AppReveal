#!/usr/bin/env bash

set -euo pipefail

session_url="${1:-${APPREVEAL_SESSION_URL:-}}"
lan_host="${2:-${APPREVEAL_LAN_HOST:-}}"

if [[ -z "$session_url" ]]; then
    printf 'Usage: %s <AppReveal session URL> [LAN host or IP]\n' "$0" >&2
    exit 2
fi

token="$(printf '%s' "$session_url" | sed -E 's#.*[?&]appreveal_session_token=([^&[:space:]]+).*#\1#')"
port="$(printf '%s' "$session_url" | sed -E 's#^https?://[^/:]+:([0-9]+)/?.*#\1#')"
if [[ -z "$token" || "$token" == "$session_url" ]]; then
    printf 'Session URL does not contain appreveal_session_token\n' >&2
    exit 2
fi
if [[ -z "$port" || "$port" == "$session_url" ]]; then
    printf 'Session URL does not contain an explicit port\n' >&2
    exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

initialize_payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

verify_endpoint() {
    local base_url="$1"
    local label="$2"
    local health_file="$work_dir/${label}-health.json"
    local unauth_file="$work_dir/${label}-unauth.json"
    local initialize_file="$work_dir/${label}-initialize.json"

    curl -fsS "${base_url}health" >"$health_file"
    jq -e --argjson port "$port" \
        '.status == "ok" and
         .port == $port and
         .auth == "session-token" and
         (.bonjour | type == "string") and
         (.bonjourDiagnostics | type == "object") and
         (.lan | type == "object")' \
        "$health_file" >/dev/null

    local unauth_status
    unauth_status="$(curl -sS -o "$unauth_file" -w '%{http_code}' \
        -H 'Content-Type: application/json' \
        -d "$initialize_payload" \
        "$base_url")"
    if [[ "$unauth_status" != "401" ]]; then
        printf '%s unauthenticated initialize returned HTTP %s, expected 401\n' "$label" "$unauth_status" >&2
        exit 1
    fi
    jq -e '.error.message == "Unauthorized"' "$unauth_file" >/dev/null

    curl -fsS "$base_url" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        -d "$initialize_payload" \
        >"$initialize_file"
    jq -e \
        '.result.protocolVersion == "2025-06-18" and
         .result.serverInfo.name == "AppReveal"' \
        "$initialize_file" >/dev/null

    local bonjour_status
    bonjour_status="$(jq -r '.bonjour' "$health_file")"
    printf '%s MCP verified on %s (Bonjour: %s)\n' "$label" "$base_url" "$bonjour_status"
}

verify_endpoint "http://127.0.0.1:$port/" "loopback"

if [[ -n "$lan_host" ]]; then
    if [[ "$lan_host" == *:* && "$lan_host" != \[*\] ]]; then
        lan_host="[$lan_host]"
    fi
    verify_endpoint "http://$lan_host:$port/" "lan"
fi
