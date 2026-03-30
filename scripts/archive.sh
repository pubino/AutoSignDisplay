#!/usr/bin/env zsh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Autostream — Archive & Export
#  Creates an xcarchive and exports a signed IPA for
#  App Store Connect upload.
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
ARCHIVE_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$ARCHIVE_DIR/Autostream.xcarchive"
EXPORT_DIR="$ARCHIVE_DIR/export"
EXPORT_OPTIONS=""
DRY_RUN=0

print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}${BOLD}║       Autostream — Archive & Export         ║${RESET}"
    echo "${MAGENTA}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
}

usage() {
    echo "${CYAN}Usage:${RESET} $0 [OPTIONS]"
    echo ""
    echo "${BOLD}Options:${RESET}"
    echo "  ${GREEN}--export-options <path>${RESET}  Path to ExportOptions.plist"
    echo "  ${GREEN}--archive-path <path>${RESET}    Custom archive output path"
    echo "  ${GREEN}--export-dir <path>${RESET}      Custom export output directory"
    echo "  ${GREEN}--dry-run${RESET}                Print commands without executing"
    echo "  ${GREEN}-h, --help${RESET}               Show this help"
    echo ""
    echo "${BOLD}Export Options:${RESET}"
    echo "  If --export-options is not provided, the script will generate"
    echo "  a default ExportOptions.plist for App Store distribution."
    echo "  You can customize signing by providing your own plist."
    echo ""
    echo "${BOLD}Prerequisites:${RESET}"
    echo "  • Valid Apple Developer account configured in Xcode"
    echo "  • Automatic signing or provisioning profile for tvOS"
    echo "  • App Store Connect team enrolled in Apple Developer Program"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --export-options) EXPORT_OPTIONS="$2"; shift 2 ;;
        --archive-path) ARCHIVE_PATH="$2"; shift 2 ;;
        --export-dir) EXPORT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) print_header; usage; exit 0 ;;
        *) echo "${RED}Unknown argument: $1${RESET}"; usage; exit 2 ;;
    esac
done

print_header

# ── Step 1: Preflight checks ───────────────────────
echo "${BLUE}Step 1/4${RESET} ${BOLD}Preflight checks${RESET}"
echo "─────────────────────────────────────────────"

# Verify Xcode is available
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || true)
if [[ -z "$XCODE_VERSION" ]]; then
    echo "${RED}✗${RESET} Xcode not found. Install Xcode from the App Store."
    exit 1
fi
echo "${GREEN}✓${RESET} $XCODE_VERSION"

# Check for tvOS SDK
TVOS_SDK=$(xcrun --sdk appletvos --show-sdk-version 2>/dev/null || true)
if [[ -z "$TVOS_SDK" ]]; then
    echo "${RED}✗${RESET} tvOS SDK not found."
    exit 1
fi
echo "${GREEN}✓${RESET} tvOS SDK $TVOS_SDK"

# Create build directory
mkdir -p "$ARCHIVE_DIR"
echo "${GREEN}✓${RESET} Build directory: $ARCHIVE_DIR"
echo ""

# ── Step 2: Archive ─────────────────────────────────
echo "${BLUE}Step 2/4${RESET} ${BOLD}Create archive${RESET}"
echo "─────────────────────────────────────────────"

ARCHIVE_CMD=(xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -sdk appletvos
    -configuration Release
    -archivePath "$ARCHIVE_PATH"
    archive
)

echo "${BLUE}⟳${RESET} Archiving ${BOLD}$SCHEME${RESET} (Release)..."
echo "${CYAN}   Output:${RESET} $ARCHIVE_PATH"
echo ""

if [[ $DRY_RUN -eq 1 ]]; then
    echo "${CYAN}DRY:${RESET} ${ARCHIVE_CMD[*]}"
else
    if "${ARCHIVE_CMD[@]}" 2>&1 | tee /tmp/autostream-archive.log | grep -E '(error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED|warning:.*error)'; then
        echo ""
    else
        true
    fi

    if [[ ! -d "$ARCHIVE_PATH" ]]; then
        echo "${RED}✗${RESET} Archive failed. Check log: /tmp/autostream-archive.log"
        exit 1
    fi
fi
echo "${GREEN}✓${RESET} Archive created"
echo ""

# ── Step 3: Generate export options ─────────────────
echo "${BLUE}Step 3/4${RESET} ${BOLD}Prepare export options${RESET}"
echo "─────────────────────────────────────────────"

if [[ -z "$EXPORT_OPTIONS" ]]; then
    EXPORT_OPTIONS="$ARCHIVE_DIR/ExportOptions.plist"
    echo "${BLUE}⟳${RESET} Generating default ExportOptions.plist..."

    if [[ $DRY_RUN -eq 0 ]]; then
        cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST
    fi
    echo "${GREEN}✓${RESET} Generated: $EXPORT_OPTIONS"
    echo ""
    echo "${YELLOW}  ⚠ Review the export options before proceeding:${RESET}"
    echo "${CYAN}    method:${RESET}       app-store-connect"
    echo "${CYAN}    signingStyle:${RESET} automatic"
    echo "${CYAN}    destination:${RESET}  upload"
    echo ""

    if [[ $DRY_RUN -eq 0 ]]; then
        echo -n "${BOLD}Continue with export? [Y/n]:${RESET} "
        read -r CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn] ]]; then
            echo "${YELLOW}Aborted.${RESET} Edit $EXPORT_OPTIONS and re-run."
            exit 0
        fi
    fi
else
    if [[ ! -f "$EXPORT_OPTIONS" ]]; then
        echo "${RED}✗${RESET} Export options not found: $EXPORT_OPTIONS"
        exit 1
    fi
    echo "${GREEN}✓${RESET} Using: $EXPORT_OPTIONS"
fi
echo ""

# ── Step 4: Export ──────────────────────────────────
echo "${BLUE}Step 4/4${RESET} ${BOLD}Export IPA${RESET}"
echo "─────────────────────────────────────────────"

mkdir -p "$EXPORT_DIR"

EXPORT_CMD=(xcodebuild
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS"
    -exportPath "$EXPORT_DIR"
)

echo "${BLUE}⟳${RESET} Exporting to: $EXPORT_DIR"
echo ""

if [[ $DRY_RUN -eq 1 ]]; then
    echo "${CYAN}DRY:${RESET} ${EXPORT_CMD[*]}"
else
    if "${EXPORT_CMD[@]}" 2>&1 | tee /tmp/autostream-export.log | grep -E '(error:|EXPORT SUCCEEDED|EXPORT FAILED)'; then
        echo ""
    else
        true
    fi

    IPA_FILE=$(find "$EXPORT_DIR" -name "*.ipa" -type f 2>/dev/null | head -1)
    if [[ -z "$IPA_FILE" ]]; then
        echo "${RED}✗${RESET} Export failed. Check log: /tmp/autostream-export.log"
        echo ""
        echo "${YELLOW}Common issues:${RESET}"
        echo "  • No valid signing identity — open Xcode and configure signing"
        echo "  • No provisioning profile — ensure automatic signing is enabled"
        echo "  • Team not set — check Signing & Capabilities in Xcode"
        exit 1
    fi
fi

echo ""
echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ ARCHIVE & EXPORT COMPLETE                ${RESET}"
echo "${GREEN}${BOLD}══════════════════════════════════════════════${RESET}"
echo ""
echo "${CYAN}Archive:${RESET}        $ARCHIVE_PATH"
echo "${CYAN}Export:${RESET}         $EXPORT_DIR"
if [[ $DRY_RUN -eq 0 ]]; then
    echo "${CYAN}IPA:${RESET}            ${IPA_FILE:-N/A}"
fi
echo ""
echo "${BOLD}Next step:${RESET} Run ${GREEN}./scripts/upload.sh${RESET} to upload to App Store Connect"
