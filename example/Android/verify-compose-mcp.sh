#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${JAVA_HOME:-}" && -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
ADB="${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}/platform-tools/adb"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
PACKAGE="com.appreveal.example"
ACTIVITY="$PACKAGE/.screens.ComposeActivity"
APK="$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk"

"$SCRIPT_DIR/gradlew" -p "$SCRIPT_DIR" :app:assembleDebug
"$ADB" -s "$SERIAL" install -r "$APK" >/dev/null
"$ADB" -s "$SERIAL" logcat -c >/dev/null 2>&1 || true
"$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE"
"$ADB" -s "$SERIAL" shell am start -W -n "$ACTIVITY" >/dev/null

session_url=""
for _ in {1..30}; do
    session_url="$(
        "$ADB" -s "$SERIAL" logcat -d -s AppReveal:I '*:S' |
            sed -n 's/.*Session URL: //p' |
            tail -1 |
            tr -d '\r'
    )"
    if [[ -n "$session_url" ]]; then
        break
    fi
    sleep 1
done

[[ -n "$session_url" ]] || { printf 'AppReveal session URL was not logged\n' >&2; exit 1; }

port="$(printf '%s' "$session_url" | sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#')"
token="$(printf '%s' "$session_url" | sed -E 's#.*appreveal_session_token=([^[:space:]]+).*#\1#')"
base_url="http://127.0.0.1:$port/"
"$ADB" -s "$SERIAL" forward "tcp:$port" "tcp:$port" >/dev/null

"$SCRIPT_DIR/../../scripts/verify-screenshot-mcp.sh" "$session_url" png
"$SCRIPT_DIR/../../scripts/verify-screenshot-mcp.sh" "$session_url" jpeg

call_tool() {
    local name="$1"
    local arguments="$2"
    curl -fsS "$base_url" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$name\",\"arguments\":$arguments}}" |
        jq -e '.result.content[0].text | fromjson'
}

call_tool get_screen '{}' | jq -e '.screenKey == "compose.test" and .frameworkType == "compose"' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .id == "compose.message" and .type == "textField" and (.actions | contains("type"))) and any(.elements[]; .id == "compose.send" and .tappable == "true")' >/dev/null
call_tool get_view_tree '{}' |
    jq -e 'any(.views[]; .framework == "compose" and .accessibilityId == "compose.message")' >/dev/null

call_tool type_text '{"element_id":"compose.message","text":"hello compose"}' | jq -e '.success == true' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .id == "compose.message" and .value == "hello compose")' >/dev/null

call_tool tap_text '{"text":"Send a message","match_mode":"exact"}' | jq -e '.success == true' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .label == "Sent: hello compose") and any(.elements[]; .label == "Send count: 1")' >/dev/null

call_tool tap_element '{"element_id":"compose.message"}' | jq -e '.success == true' >/dev/null
call_tool type_text '{"text":" focused"}' | jq -e '.success == true' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .id == "compose.message" and .value == "hello compose focused")' >/dev/null

call_tool tap_element '{"element_id":"compose.send"}' | jq -e '.success == true' >/dev/null
call_tool tap_element '{"element_id":"duplicate_action_1"}' | jq -e '.success == true' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .label == "Send count: 2") and any(.elements[]; .label == "Duplicate result: second")' >/dev/null

call_tool clear_text '{"element_id":"compose.message"}' | jq -e '.success == true' >/dev/null
call_tool get_elements '{}' |
    jq -e 'any(.elements[]; .id == "compose.message" and .value == "")' >/dev/null

printf 'Compose MCP verification passed on %s (API %s)\n' \
    "$SERIAL" \
    "$("$ADB" -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')"
