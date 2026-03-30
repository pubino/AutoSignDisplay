#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Upload to App Store Connect
#  Uploads the exported IPA to App Store Connect for
#  TestFlight or App Store distribution.
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
EXPORT_DIR="$PROJECT_DIR/build/export"
IPA_FILE=""
APPLE_ID=""
APP_PASSWORD=""
TEAM_ID=""
DRY_RUN=0

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║   Autostream — Upload to App Store Connect  ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--ipa <path>${RESET}             Path to IPA file"
    echo "  ${GREEN}--apple-id <email>${RESET}       Apple ID email"
    echo "  ${GREEN}--password <secret>${RESET}      App-specific password or @keychain:<name>"
    echo "  ${GREEN}--team-id <id>${RESET}           App Store Connect team ID (for multiple teams)"
    echo "  ${GREEN}--dry-run${RESET}                Print commands without executing"
    echo "  ${GREEN}-h, --help${RESET}               Show this help"
    echo ""
    echo "${BOLD}Authentication:${RESET}"
    echo "  You need an app-specific password for upload. To create one:"
    echo "  1. Go to ${CYAN}https://appleid.apple.com${RESET}"
    echo "  2. Sign In > Security > App-Specific Passwords"
    echo "  3. Generate a new password"
    echo ""
    echo "  Store it in your keychain for convenience:"
    echo "    ${CYAN}xcrun notarytool store-credentials \"Autostream\"${RESET}"
    echo ""
    echo "  Or use the ${CYAN}AUTOSTREAM_APPLE_ID${RESET} and ${CYAN}AUTOSTREAM_APP_PASSWORD${RESET}"
    echo "  environment variables."
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ipa) IPA_FILE="$2"; shift 2 ;;
        --apple-id) APPLE_ID="$2"; shift 2 ;;
        --password) APP_PASSWORD="$2"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

# ── Step 1: Find IPA ───────────────────────────────
echo "${BLUE}Step 1/3${RESET} ${BOLD}Locate IPA${RESET}"
echo "─────────────────────────────────────────────"

if [[ -z "$IPA_FILE" ]]; then
    IPA_FILE=$(find "$EXPORT_DIR" -name "*.ipa" -type f 2>/dev/null | head -1 || true)
fi

if [[ -z "$IPA_FILE" || ! -f "$IPA_FILE" ]]; then
    echo "${RED}✗${RESET} No IPA file found."
    echo ""
    echo "${YELLOW}  Hint:${RESET} Run ${GREEN}./scripts/archive.sh${RESET} first to create the IPA."
    echo "  Or specify the path: ${GREEN}$0 --ipa /path/to/Autostream.ipa${RESET}"
    exit 1
fi

IPA_SIZE=$(du -h "$IPA_FILE" | cut -f1)
echo "${GREEN}✓${RESET} IPA found: ${BOLD}$IPA_FILE${RESET} (${IPA_SIZE})"
echo ""

# ── Step 2: Credentials ────────────────────────────
echo "${BLUE}Step 2/3${RESET} ${BOLD}Verify credentials${RESET}"
echo "─────────────────────────────────────────────"

# Check environment variables as fallback
if [[ -z "$APPLE_ID" ]]; then
    APPLE_ID="${AUTOSTREAM_APPLE_ID:-}"
fi
if [[ -z "$APP_PASSWORD" ]]; then
    APP_PASSWORD="${AUTOSTREAM_APP_PASSWORD:-}"
fi

# Interactive prompts if not provided
if [[ -z "$APPLE_ID" ]]; then
    echo -n "${BOLD}Apple ID (email):${RESET} "
    read -r APPLE_ID
fi

if [[ -z "$APPLE_ID" ]]; then
    echo "${RED}✗${RESET} Apple ID is required."
    exit 1
fi
echo "${GREEN}✓${RESET} Apple ID: ${BOLD}$APPLE_ID${RESET}"

if [[ -z "$APP_PASSWORD" ]]; then
    echo ""
    echo "${YELLOW}  Authentication options:${RESET}"
    echo "  ${CYAN}1.${RESET} Enter an app-specific password"
    echo "  ${CYAN}2.${RESET} Use keychain: @keychain:Autostream"
    echo "  ${CYAN}3.${RESET} Use API key (set ASC_API_KEY_PATH env var)"
    echo ""
    echo -n "${BOLD}App-specific password (or @keychain:<name>):${RESET} "
    read -rs APP_PASSWORD
    echo ""
fi

if [[ -z "$APP_PASSWORD" ]]; then
    echo "${RED}✗${RESET} Password is required."
    echo "${YELLOW}  Hint:${RESET} Create one at https://appleid.apple.com"
    exit 1
fi
echo "${GREEN}✓${RESET} Credentials ready"
echo ""

# ── Step 3: Upload ──────────────────────────────────
echo "${BLUE}Step 3/3${RESET} ${BOLD}Upload to App Store Connect${RESET}"
echo "─────────────────────────────────────────────"

# Build the upload command
UPLOAD_CMD=(xcrun altool
    --upload-app
    --type tvos
    --file "$IPA_FILE"
    --username "$APPLE_ID"
    --password "$APP_PASSWORD"
)

if [[ -n "$TEAM_ID" ]]; then
    UPLOAD_CMD+=(--asc-provider "$TEAM_ID")
fi

echo "${BLUE}⟳${RESET} Uploading to App Store Connect..."
echo "${CYAN}   File:${RESET} $IPA_FILE"
echo "${CYAN}   User:${RESET} $APPLE_ID"
if [[ -n "$TEAM_ID" ]]; then
    echo "${CYAN}   Team:${RESET} $TEAM_ID"
fi
echo ""

if [[ $DRY_RUN -eq 1 ]]; then
    echo "${CYAN}DRY:${RESET} xcrun altool --upload-app --type tvos --file $IPA_FILE --username $APPLE_ID --password ****"
    echo ""
    echo "${GREEN}✓${RESET} Dry run complete"
    exit 0
fi

# Upload with progress reporting
if "${UPLOAD_CMD[@]}" 2>&1 | tee /tmp/autostream-upload.log; then
    echo ""
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    echo "${GREEN}${BOLD}  ✓ UPLOAD SUCCESSFUL                        ${RESET}"
    echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
    echo ""
    echo "${BOLD}What's next:${RESET}"
    echo "  ${CYAN}1.${RESET} Wait for App Store Connect processing (5-30 minutes)"
    echo "  ${CYAN}2.${RESET} Check status at ${CYAN}https://appstoreconnect.apple.com${RESET}"
    echo "  ${CYAN}3.${RESET} Enable the build for TestFlight or submit for review"
    echo ""
    echo "${CYAN}Tip:${RESET} You'll receive an email when processing completes."
else
    UPLOAD_EXIT=$?
    echo ""
    echo "${RED}${BOLD}══════════════════════════════════════════════${RESET}"
    echo "${RED}${BOLD}  ✗ UPLOAD FAILED                            ${RESET}"
    echo "${RED}${BOLD}══════════════════════════════════════════════${RESET}"
    echo ""
    echo "${YELLOW}Common issues:${RESET}"
    echo "  • ${BOLD}Authentication failed${RESET} — verify Apple ID and app-specific password"
    echo "  • ${BOLD}No account found${RESET} — check team membership at developer.apple.com"
    echo "  • ${BOLD}Bundle ID conflict${RESET} — ensure edu.princeton.orfe.Autostream is registered"
    echo "  • ${BOLD}Version exists${RESET} — increment MARKETING_VERSION or CURRENT_PROJECT_VERSION"
    echo ""
    echo "${CYAN}Full log:${RESET} /tmp/autostream-upload.log"
    exit $UPLOAD_EXIT
fi
