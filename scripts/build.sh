#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Build Script
#  Builds the Autostream tvOS app for simulator or device.
# ─────────────────────────────────────────────────────────────

# Colors
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
CONFIGURATION="Debug"
SDK="appletvsimulator"

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║       Autostream — Build                    ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--release${RESET}        Build with Release configuration"
    echo "  ${GREEN}--device${RESET}         Build for tvOS device (requires signing)"
    echo "  ${GREEN}--clean${RESET}          Clean build folder first"
    echo "  ${GREEN}--dry-run${RESET}        Print commands without executing"
    echo "  ${GREEN}-h, --help${RESET}       Show this help"
    echo ""
}

DRY_RUN=0
CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) CONFIGURATION="Release"; shift ;;
        --device) SDK="appletvos"; shift ;;
        --clean) CLEAN=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

echo "${BLUE}▸${RESET} Project:       ${BOLD}$PROJECT${RESET}"
echo "${BLUE}▸${RESET} Scheme:        ${BOLD}$SCHEME${RESET}"
echo "${BLUE}▸${RESET} Configuration: ${BOLD}$CONFIGURATION${RESET}"
echo "${BLUE}▸${RESET} SDK:           ${BOLD}$SDK${RESET}"
echo ""

if [[ $CLEAN -eq 1 ]]; then
    echo "${YELLOW}⟳${RESET} Cleaning build folder..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${CYAN}DRY:${RESET} xcodebuild clean"
    else
        xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk "$SDK" clean 2>&1 | tail -3
        echo "${GREEN}✓${RESET} Clean complete"
    fi
    echo ""
fi

echo "${BLUE}⟳${RESET} Building ${BOLD}$SCHEME${RESET} (${CONFIGURATION})..."
echo ""

CMD=(xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -sdk "$SDK"
    -configuration "$CONFIGURATION"
    CODE_SIGNING_ALLOWED=NO
    build
)

if [[ $DRY_RUN -eq 1 ]]; then
    echo "${CYAN}DRY:${RESET} ${CMD[*]}"
    echo ""
    echo "${GREEN}✓${RESET} Dry run complete"
    exit 0
fi

if "${CMD[@]}" 2>&1 | tee /tmp/autostream-build.log | grep -E '(error:|warning:.*Autostream|BUILD SUCCEEDED|BUILD FAILED)'; then
    echo ""
else
    true
fi

if grep -q "BUILD SUCCEEDED" /tmp/autostream-build.log 2>/dev/null; then
    echo "${GREEN}${BOLD}✓ BUILD SUCCEEDED${RESET}"
    echo ""
    echo "${CYAN}Build log:${RESET} /tmp/autostream-build.log"
else
    echo "${RED}${BOLD}✗ BUILD FAILED${RESET}"
    echo ""
    echo "${YELLOW}Check full log:${RESET} /tmp/autostream-build.log"
    exit 1
fi
