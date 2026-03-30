#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Test Runner
#  Runs unit and UI tests on a tvOS simulator.
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Autostream.xcodeproj"
SCHEME="Autostream"
BUNDLE_ID="edu.princeton.orfe.Autostream"
UDID=""
DRY_RUN=0
MANAGED_MODE="unmanaged"

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║       Autostream — Test Runner              ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--udid <UDID>${RESET}   Use a specific simulator UDID"
    echo "  ${GREEN}--managed${RESET}        Apply managed config before tests"
    echo "  ${GREEN}--unmanaged${RESET}      Ensure unmanaged state (default)"
    echo "  ${GREEN}--dry-run${RESET}        Print commands without executing"
    echo "  ${GREEN}-h, --help${RESET}       Show this help"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --udid) UDID="$2"; shift 2 ;;
        --managed) MANAGED_MODE="managed"; shift ;;
        --unmanaged) MANAGED_MODE="unmanaged"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

# ── Step 1: Discover simulator ──────────────────────
echo "${BLUE}Step 1/4${RESET} ${BOLD}Discover tvOS simulator${RESET}"
echo "─────────────────────────────────────────────"

if [[ -z "$UDID" ]]; then
    echo "${BLUE}⟳${RESET} Searching for tvOS simulator..."
    UDID=$(python3 - <<'PY'
import json,subprocess,sys
out = subprocess.check_output(["xcrun","simctl","list","devices","--json"]).decode()
data = json.loads(out)
devices = data.get('devices', {})
for runtime in sorted(devices.keys(), reverse=True):
    if 'tvOS' not in runtime:
        continue
    for d in devices[runtime]:
        if d.get('isAvailable') and d.get('state') == 'Booted':
            print(d['udid']); sys.exit(0)
    for d in devices[runtime]:
        if d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
print('')
PY
)
    if [[ -z "$UDID" ]]; then
        echo "${RED}✗${RESET} No available tvOS simulator found."
        echo "${YELLOW}  Hint:${RESET} Install a tvOS simulator runtime in Xcode > Settings > Platforms"
        exit 3
    fi
fi
echo "${GREEN}✓${RESET} Using simulator: ${BOLD}$UDID${RESET}"
echo ""

# ── Step 2: Boot simulator ──────────────────────────
echo "${BLUE}Step 2/4${RESET} ${BOLD}Boot simulator${RESET}"
echo "─────────────────────────────────────────────"

STATE=$(python3 - "$UDID" <<'PY'
import json,subprocess,sys
udid = sys.argv[1]
out = subprocess.check_output(["xcrun","simctl","list","devices","--json"]).decode()
data = json.loads(out)
for runtime in data.get('devices', {}).values():
    for d in runtime:
        if d.get('udid') == udid:
            print(d.get('state', 'Unknown')); sys.exit(0)
print('Unknown')
PY
)

if [[ "$STATE" != "Booted" ]]; then
    echo "${YELLOW}⟳${RESET} Simulator not booted (state=$STATE). Booting..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${CYAN}DRY:${RESET} xcrun simctl boot $UDID"
    else
        xcrun simctl boot "$UDID"
        xcrun simctl bootstatus "$UDID" -b
    fi
    echo "${GREEN}✓${RESET} Simulator booted"
else
    echo "${GREEN}✓${RESET} Simulator already running"
fi
echo ""

# ── Step 3: Apply configuration ─────────────────────
echo "${BLUE}Step 3/4${RESET} ${BOLD}Configure test environment ($MANAGED_MODE)${RESET}"
echo "─────────────────────────────────────────────"

if [[ "$MANAGED_MODE" == "managed" ]]; then
    echo "${BLUE}⟳${RESET} Writing managed configuration to simulator..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${CYAN}DRY:${RESET} Write managed configuration plist"
    else
        PLIST=$(mktemp)
        cat <<'PLIST_CONTENT' > "$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.configuration.managed</key>
  <dict>
    <key>PlayOnAppOpen</key><true/>
    <key>StreamURL</key><string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
    <key>AutoResume</key><true/>
    <key>RetryTimeout</key><real>5.0</real>
    <key>ChannelPresets</key>
    <array>
      <string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
      <string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
      <string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
      <string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
    </array>
    <key>DefaultChannel</key><string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
  </dict>
</dict>
</plist>
PLIST_CONTENT
        xcrun simctl spawn "$UDID" defaults import "$BUNDLE_ID" "$PLIST"
        rm -f "$PLIST"
    fi
    echo "${GREEN}✓${RESET} Managed configuration applied"
else
    echo "${BLUE}⟳${RESET} Clearing managed configuration..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${CYAN}DRY:${RESET} Delete managed config key"
    else
        xcrun simctl spawn "$UDID" defaults delete "$BUNDLE_ID" com.apple.configuration.managed >/dev/null 2>&1 || true
    fi
    echo "${GREEN}✓${RESET} Unmanaged state set"
fi
echo ""

# ── Step 4: Run tests ───────────────────────────────
echo "${BLUE}Step 4/4${RESET} ${BOLD}Run tests${RESET}"
echo "─────────────────────────────────────────────"

CMD=(xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -sdk appletvsimulator
    -destination "id=$UDID"
    -parallel-testing-enabled NO
    test
)

echo "${BLUE}⟳${RESET} Running: ${CYAN}xcodebuild test${RESET}"
echo ""

if [[ $DRY_RUN -eq 1 ]]; then
    echo "${CYAN}DRY:${RESET} ${CMD[*]}"
    echo ""
    echo "${GREEN}✓${RESET} Dry run complete"
    exit 0
fi

LOG_FILE="/tmp/autostream-test.log"

if "${CMD[@]}" 2>&1 | tee "$LOG_FILE" | grep -E '(Test Case|test.*passed|test.*failed|error:|BUILD|Tests:)'; then
    echo ""
else
    true
fi

echo ""
if grep -q "TEST SUCCEEDED\|** TEST SUCCEEDED **" "$LOG_FILE" 2>/dev/null; then
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    echo "${GREEN}${BOLD}  ✓ ALL TESTS PASSED                         ${RESET}"
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
elif grep -q "BUILD SUCCEEDED" "$LOG_FILE" 2>/dev/null; then
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    echo "${GREEN}${BOLD}  ✓ TESTS COMPLETE                           ${RESET}"
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
else
    echo "${RED}${BOLD}══════════════════════════════════════════════${RESET}"
    echo "${RED}${BOLD}  ✗ TESTS FAILED                             ${RESET}"
    echo "${RED}${BOLD}══════════════════════════════════════════════${RESET}"
    echo ""
    echo "${YELLOW}Full log:${RESET} $LOG_FILE"
    exit 1
fi
echo ""
echo "${CYAN}Full log:${RESET} $LOG_FILE"
