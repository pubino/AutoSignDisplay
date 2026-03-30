#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Run on Simulator
#  Boots a tvOS simulator and installs/launches the app.
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

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║       Autostream — Run on Simulator         ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--udid <UDID>${RESET}   Use a specific simulator UDID"
    echo "  ${GREEN}--managed${RESET}        Apply managed configuration before launch"
    echo "  ${GREEN}-h, --help${RESET}       Show this help"
    echo ""
}

MANAGED_MODE="unmanaged"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --udid) UDID="$2"; shift 2 ;;
        --managed) MANAGED_MODE="managed"; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

# ── Discover simulator ──────────────────────────────
if [[ -z "$UDID" ]]; then
    echo "${BLUE}⟳${RESET} Discovering tvOS simulator..."
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
        echo "${RED}✗${RESET} No available tvOS simulator found"
        exit 3
    fi
fi
echo "${GREEN}✓${RESET} Simulator: ${BOLD}$UDID${RESET}"

# ── Boot simulator ──────────────────────────────────
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
    echo "${YELLOW}⟳${RESET} Booting simulator..."
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b
    echo "${GREEN}✓${RESET} Simulator booted"
else
    echo "${GREEN}✓${RESET} Simulator already booted"
fi

# ── Apply managed config if requested ───────────────
if [[ "$MANAGED_MODE" == "managed" ]]; then
    echo "${BLUE}⟳${RESET} Applying managed configuration..."
    PLIST=$(mktemp)
    cat <<'PLIST' > "$PLIST"
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
    </array>
    <key>DefaultChannel</key><string>https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8</string>
  </dict>
</dict>
</plist>
PLIST
    xcrun simctl spawn "$UDID" defaults import "$BUNDLE_ID" "$PLIST"
    rm -f "$PLIST"
    echo "${GREEN}✓${RESET} Managed configuration applied"
fi

# ── Build and install ───────────────────────────────
echo "${BLUE}⟳${RESET} Building and installing..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk appletvsimulator \
    -destination "id=$UDID" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tail -3

# Find and install the built app
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk appletvsimulator -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $NF}')
APP_PATH="$BUILD_DIR/Autostream.app"

if [[ -d "$APP_PATH" ]]; then
    echo "${BLUE}⟳${RESET} Installing app..."
    xcrun simctl install "$UDID" "$APP_PATH"
    echo "${GREEN}✓${RESET} App installed"

    echo "${BLUE}⟳${RESET} Launching app..."
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    echo "${GREEN}✓${RESET} App launched"
else
    echo "${YELLOW}⚠${RESET}  Could not find built app at: $APP_PATH"
    echo "${YELLOW}  ${RESET} Try opening Xcode and running manually."
fi

echo ""
echo "${GREEN}${BOLD}Done!${RESET} Autostream is running on the simulator."
echo "${CYAN}Tip:${RESET} Open Simulator.app to see the tvOS interface."
