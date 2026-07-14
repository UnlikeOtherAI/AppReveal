#!/usr/bin/env bash

set -euo pipefail

mode="${1:-run}"
app_name="AppRevealMacExample"
bundle_id="com.appreveal.macos.example"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example_dir="$root_dir/example/macOS/AppRevealMacExample"
project_path="$example_dir/AppRevealMacExample.xcodeproj"
derived_data="$root_dir/.build/AppRevealMacExample"
app_bundle="$derived_data/Build/Products/Debug/$app_name.app"
app_binary="$app_bundle/Contents/MacOS/$app_name"
log_dir="${TMPDIR:-/tmp}"
log_dir="${log_dir%/}"
stdout_log="$log_dir/$app_name.stdout.log"
stderr_log="$log_dir/$app_name.stderr.log"

if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'xcodegen is required. Install it with: brew install xcodegen\n' >&2
    exit 1
fi

pkill -x "$app_name" >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -x "$app_name" >/dev/null; then
        break
    fi
    sleep 0.1
done

(
    cd "$example_dir"
    xcodegen generate
)

xcodebuild \
    -project "$project_path" \
    -scheme "$app_name" \
    -configuration Debug \
    -derivedDataPath "$derived_data" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    build

open_app() {
    mkdir -p "$log_dir"
    : >"$stdout_log"
    : >"$stderr_log"
    if ! /usr/bin/open -n \
            -o "$stdout_log" \
            --stderr "$stderr_log" \
            --env NSUnbufferedIO=YES \
            "$app_bundle"; then
        # LaunchServices can briefly retain the prior instance immediately after a rebuild.
        sleep 1
        /usr/bin/open -n \
            -o "$stdout_log" \
            --stderr "$stderr_log" \
            --env NSUnbufferedIO=YES \
            "$app_bundle"
    fi
}

verify_process() {
    local attempt
    for attempt in {1..20}; do
        if pgrep -x "$app_name" >/dev/null; then
            printf '%s is running.\n' "$app_name"
            printf 'stdout: %s\nstderr: %s\n' "$stdout_log" "$stderr_log"
            return 0
        fi
        sleep 0.5
    done
    printf '%s did not remain running after launch.\n' "$app_name" >&2
    return 1
}

case "$mode" in
    run)
        open_app
        printf 'Launched %s.\nstdout: %s\nstderr: %s\n' "$app_bundle" "$stdout_log" "$stderr_log"
        ;;
    --debug|debug)
        lldb -- "$app_binary"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$app_name\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
        ;;
    --verify|verify)
        open_app
        verify_process
        ;;
    *)
        printf 'Usage: %s [run|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
        exit 2
        ;;
esac
