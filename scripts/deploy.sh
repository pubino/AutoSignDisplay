#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Full Deployment Pipeline
#  End-to-end: Test → Archive → Export → Upload to App Connect
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=0
SKIP_TESTS=0
APPLE_ID=""
APP_PASSWORD=""
TEAM_ID=""

print_banner() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║                                                      ║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE}  █████╗ ██╗   ██╗████████╗ ██████╗               ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE} ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗              ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE} ███████║██║   ██║   ██║   ██║   ██║              ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE} ██╔══██║██║   ██║   ██║   ██║   ██║              ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE} ██║  ██║╚██████╔╝   ██║   ╚██████╔╝              ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${WHITE} ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝               ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║   ${CYAN}       STREAM — Deploy to App Store Connect       ${MAGENTA}║${RESET}"
    echo "${MAGENTA}${BOLD}║                                                      ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--skip-tests${RESET}         Skip running tests"
    echo "  ${GREEN}--apple-id <email>${RESET}   Apple ID for upload"
    echo "  ${GREEN}--password <secret>${RESET}  App-specific password"
    echo "  ${GREEN}--team-id <id>${RESET}       ASC team ID"
    echo "  ${GREEN}--dry-run${RESET}            Print all commands without executing"
    echo "  ${GREEN}-h, --help${RESET}           Show this help"
    echo ""
    echo "${BOLD}Pipeline steps:${RESET}"
    echo "  ${BLUE}1.${RESET} ${BOLD}Preflight${RESET}  — Check tools, signing, environment"
    echo "  ${BLUE}2.${RESET} ${BOLD}Test${RESET}       — Run unit tests on tvOS simulator"
    echo "  ${BLUE}3.${RESET} ${BOLD}Archive${RESET}    — Create signed xcarchive"
    echo "  ${BLUE}4.${RESET} ${BOLD}Export${RESET}     — Generate IPA with ExportOptions"
    echo "  ${BLUE}5.${RESET} ${BOLD}Upload${RESET}     — Send IPA to App Store Connect"
    echo ""
    echo "${BOLD}Environment variables:${RESET}"
    echo "  ${CYAN}AUTOSTREAM_APPLE_ID${RESET}       Apple ID email"
    echo "  ${CYAN}AUTOSTREAM_APP_PASSWORD${RESET}   App-specific password"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests) SKIP_TESTS=1; shift ;;
        --apple-id) APPLE_ID="$2"; shift 2 ;;
        --password) APP_PASSWORD="$2"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) print_banner; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_banner

TOTAL_STEPS=5
if [[ $SKIP_TESTS -eq 1 ]]; then
    TOTAL_STEPS=4
fi

step_num=0
next_step() {
    step_num=$((step_num + 1))
    echo ""
    echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${BLUE}  Step ${step_num}/${TOTAL_STEPS}: ${BOLD}$1${RESET}"
    echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════
# Step 1: Preflight
# ═══════════════════════════════════════════════════
next_step "Preflight Checks"

echo "${BLUE}▸${RESET} Checking Xcode..."
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || true)
if [[ -z "$XCODE_VERSION" ]]; then
    echo "${RED}  ✗ Xcode not found${RESET}"
    exit 1
fi
echo "${GREEN}  ✓${RESET} $XCODE_VERSION"

echo "${BLUE}▸${RESET} Checking tvOS SDK..."
TVOS_SDK=$(xcrun --sdk appletvos --show-sdk-version 2>/dev/null || true)
if [[ -z "$TVOS_SDK" ]]; then
    echo "${RED}  ✗ tvOS SDK not found${RESET}"
    exit 1
fi
echo "${GREEN}  ✓${RESET} tvOS SDK $TVOS_SDK"

echo "${BLUE}▸${RESET} Checking project..."
if [[ ! -d "$PROJECT_DIR/Autostream.xcodeproj" ]]; then
    echo "${RED}  ✗ Project not found at $PROJECT_DIR${RESET}"
    exit 1
fi
echo "${GREEN}  ✓${RESET} Autostream.xcodeproj"

echo "${BLUE}▸${RESET} Checking altool..."
if ! xcrun altool --version >/dev/null 2>&1; then
    echo "${YELLOW}  ⚠ altool not available — upload step may fail${RESET}"
else
    echo "${GREEN}  ✓${RESET} altool available"
fi

echo ""
echo "${GREEN}All preflight checks passed.${RESET}"

# ═══════════════════════════════════════════════════
# Step 2: Tests (unless skipped)
# ═══════════════════════════════════════════════════
if [[ $SKIP_TESTS -eq 0 ]]; then
    next_step "Run Tests"

    DRY_FLAG=""
    if [[ $DRY_RUN -eq 1 ]]; then
        DRY_FLAG="--dry-run"
    fi

    if "$SCRIPT_DIR/test.sh" $DRY_FLAG; then
        echo "${GREEN}  ✓${RESET} Tests passed"
    else
        echo "${RED}  ✗ Tests failed — aborting deployment${RESET}"
        echo ""
        echo "${YELLOW}  Fix the failing tests and re-run, or use ${GREEN}--skip-tests${YELLOW} to bypass.${RESET}"
        exit 1
    fi
else
    echo "${YELLOW}  ⚠ Tests skipped (--skip-tests)${RESET}"
fi

# ═══════════════════════════════════════════════════
# Step 3: Archive
# ═══════════════════════════════════════════════════
next_step "Archive"

DRY_FLAG=""
if [[ $DRY_RUN -eq 1 ]]; then
    DRY_FLAG="--dry-run"
fi

"$SCRIPT_DIR/archive.sh" $DRY_FLAG

# ═══════════════════════════════════════════════════
# Step 4: Upload
# ═══════════════════════════════════════════════════
next_step "Upload to App Store Connect"

UPLOAD_ARGS=()
if [[ -n "$APPLE_ID" ]]; then
    UPLOAD_ARGS+=(--apple-id "$APPLE_ID")
fi
if [[ -n "$APP_PASSWORD" ]]; then
    UPLOAD_ARGS+=(--password "$APP_PASSWORD")
fi
if [[ -n "$TEAM_ID" ]]; then
    UPLOAD_ARGS+=(--team-id "$TEAM_ID")
fi
if [[ $DRY_RUN -eq 1 ]]; then
    UPLOAD_ARGS+=(--dry-run)
fi

"$SCRIPT_DIR/upload.sh" "${UPLOAD_ARGS[@]}"

# ═══════════════════════════════════════════════════
# Complete
# ═══════════════════════════════════════════════════
echo ""
echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}║                                                      ║${RESET}"
echo "${GREEN}${BOLD}║   ✓  DEPLOYMENT PIPELINE COMPLETE                    ║${RESET}"
echo "${GREEN}${BOLD}║                                                      ║${RESET}"
echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "${BOLD}Summary:${RESET}"
if [[ $SKIP_TESTS -eq 0 ]]; then
    echo "  ${GREEN}✓${RESET} Tests       — passed"
fi
echo "  ${GREEN}✓${RESET} Archive     — created"
echo "  ${GREEN}✓${RESET} Export      — IPA generated"
echo "  ${GREEN}✓${RESET} Upload      — sent to App Store Connect"
echo ""
echo "${BOLD}Next steps:${RESET}"
echo "  ${CYAN}1.${RESET} Wait for App Store Connect processing"
echo "  ${CYAN}2.${RESET} Visit ${CYAN}https://appstoreconnect.apple.com${RESET} to check status"
echo "  ${CYAN}3.${RESET} Enable for TestFlight or submit for App Store review"
echo ""
