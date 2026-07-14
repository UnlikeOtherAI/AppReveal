#!/usr/bin/env bash

set -euo pipefail

session_url="${1:-${APPREVEAL_SESSION_URL:-}}"
format="${2:-png}"

if [[ -z "$session_url" ]]; then
    printf 'Usage: %s <AppReveal session URL> [png|jpeg]\n' "$0" >&2
    exit 2
fi

case "$format" in
    png)
        expected_mime="image/png"
        expected_magic="89504e470d0a1a0a"
        ;;
    jpeg)
        expected_mime="image/jpeg"
        expected_magic="ffd8"
        ;;
    *)
        printf 'Format must be png or jpeg\n' >&2
        exit 2
        ;;
esac

endpoint="${session_url%%\?*}"
token="$(printf '%s' "$session_url" | sed -E 's#.*[?&]appreveal_session_token=([^&[:space:]]+).*#\1#')"
if [[ -z "$token" || "$token" == "$session_url" ]]; then
    printf 'Session URL does not contain appreveal_session_token\n' >&2
    exit 2
fi

response_file="$(mktemp)"
decoded_file="$(mktemp)"
trap 'rm -f "$response_file" "$decoded_file"' EXIT

curl -fsS "$endpoint" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"screenshot\",\"arguments\":{\"format\":\"$format\"}}}" \
    >"$response_file"

jq -e \
    --arg mime "$expected_mime" \
    '.result.content[0].type == "image" and
     .result.content[0].mimeType == $mime and
     (.result.content[0].data | type == "string" and length > 0) and
     .result.content[1].type == "text" and
     ((.result.content[1].text | fromjson) == .result.structuredContent) and
     (.result.structuredContent.image == null)' \
    "$response_file" >/dev/null

jq -r '.result.content[0].data' "$response_file" | openssl base64 -d -A >"$decoded_file"
actual_magic="$(od -An -tx1 -N8 "$decoded_file" | tr -d '[:space:]')"
if [[ "$actual_magic" != "$expected_magic"* ]]; then
    printf 'Screenshot bytes do not match %s (magic: %s)\n' "$format" "$actual_magic" >&2
    exit 1
fi

width="$(jq -r '.result.structuredContent.width' "$response_file")"
height="$(jq -r '.result.structuredContent.height' "$response_file")"
printf 'Screenshot MCP image block verified: %sx%s %s\n' "$width" "$height" "$expected_mime"
