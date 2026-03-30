#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Version Bump
#  Updates MARKETING_VERSION and/or CURRENT_PROJECT_VERSION
#  in the Xcode project before archiving.
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
PBXPROJ="$PROJECT_DIR/Autostream.xcodeproj/project.pbxproj"

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║       Autostream — Version Bump             ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--marketing <version>${RESET}   Set MARKETING_VERSION (e.g., 1.0.0)"
    echo "  ${GREEN}--build <number>${RESET}        Set CURRENT_PROJECT_VERSION (e.g., 42)"
    echo "  ${GREEN}--bump-build${RESET}            Auto-increment build number"
    echo "  ${GREEN}--show${RESET}                  Show current versions"
    echo "  ${GREEN}-h, --help${RESET}              Show this help"
    echo ""
    echo "${BOLD}Examples:${RESET}"
    echo "  $0 --marketing 1.0.0 --build 1"
    echo "  $0 --bump-build              ${DIM}# Auto-increment${RESET}"
    echo "  $0 --show                    ${DIM}# Show current versions${RESET}"
    echo ""
}

MARKETING=""
BUILD=""
BUMP_BUILD=0
SHOW_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --marketing) MARKETING="$2"; shift 2 ;;
        --build) BUILD="$2"; shift 2 ;;
        --bump-build) BUMP_BUILD=1; shift ;;
        --show) SHOW_ONLY=1; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

# Read current versions
CURRENT_MARKETING=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/ *;.*//' || echo "unknown")
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/ *;.*//' || echo "unknown")

echo "${BLUE}▸${RESET} Current marketing version: ${BOLD}$CURRENT_MARKETING${RESET}"
echo "${BLUE}▸${RESET} Current build number:      ${BOLD}$CURRENT_BUILD${RESET}"
echo ""

if [[ $SHOW_ONLY -eq 1 ]]; then
    exit 0
fi

if [[ -z "$MARKETING" && -z "$BUILD" && $BUMP_BUILD -eq 0 ]]; then
    echo "${YELLOW}No version changes specified.${RESET}"
    echo "Use ${GREEN}--marketing${RESET}, ${GREEN}--build${RESET}, or ${GREEN}--bump-build${RESET}."
    exit 0
fi

# Apply marketing version
if [[ -n "$MARKETING" ]]; then
    echo "${BLUE}⟳${RESET} Setting MARKETING_VERSION to ${BOLD}$MARKETING${RESET}..."
    sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $MARKETING/g" "$PBXPROJ"
    echo "${GREEN}✓${RESET} Marketing version set to $MARKETING"
fi

# Bump or set build number
if [[ $BUMP_BUILD -eq 1 ]]; then
    NEW_BUILD=$((CURRENT_BUILD + 1))
    echo "${BLUE}⟳${RESET} Incrementing build number: ${BOLD}$CURRENT_BUILD → $NEW_BUILD${RESET}..."
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" "$PBXPROJ"
    echo "${GREEN}✓${RESET} Build number set to $NEW_BUILD"
elif [[ -n "$BUILD" ]]; then
    echo "${BLUE}⟳${RESET} Setting CURRENT_PROJECT_VERSION to ${BOLD}$BUILD${RESET}..."
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $BUILD/g" "$PBXPROJ"
    echo "${GREEN}✓${RESET} Build number set to $BUILD"
fi

echo ""

# Read updated versions
NEW_MARKETING=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/ *;.*//')
NEW_BUILD_NUM=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/ *;.*//')

echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ VERSION UPDATED                          ${RESET}"
echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
echo ""
echo "${CYAN}Marketing version:${RESET} ${BOLD}$NEW_MARKETING${RESET}"
echo "${CYAN}Build number:${RESET}      ${BOLD}$NEW_BUILD_NUM${RESET}"
echo ""
echo "${BOLD}Next step:${RESET} Commit the change and run ${GREEN}./scripts/deploy.sh${RESET}"
