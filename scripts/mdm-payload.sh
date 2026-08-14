#!/usr/bin/env bash
set -euo pipefail

# Emit an MDM payload in a form Jamf's App Configuration field accepts, and copy it to
# the clipboard.
#
# The files in mdm/ lead with a long comment block and carry no DOCTYPE, because their
# job is to be read. Jamf validates what you paste, and rejects some shapes with
# FIELD_CONFIGURATION_PLIST_INCORRECT_FORMAT. Which shapes is not documented and has
# not been pinned down, so this script emits variants rather than assuming one.
#
# Usage (runnable from any directory):
#   ./scripts/mdm-payload.sh verify        # first-install verification
#   ./scripts/mdm-payload.sh kiosk         # locked-down display
#   ./scripts/mdm-payload.sh full          # full reference of every key
#   ./scripts/mdm-payload.sh probe         # smallest legal payload, for bisecting
#   ./scripts/mdm-payload.sh <path>        # any plist
#
#   --form dict    <dict> only, no wrapper                   (default; what Jamf takes)
#   --form plist   <?xml?> + <plist> + <dict>, no DOCTYPE
#   --form full    <?xml?> + <!DOCTYPE> + <plist> + <dict>
#   --ascii        replace non-ASCII characters with ASCII equivalents
#   --stdout       print instead of copying
#
# Bisecting a rejection: start with `probe`. If that is accepted, the format is fine and
# the problem is in the payload's content — add keys back until it breaks. If probe is
# rejected in every --form, the problem is the field, not the file.

MDM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../mdm" && pwd)"
TO_STDOUT=0
LABEL=""
FORM="dict"
ASCII=0
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --form)    FORM="${2:?--form needs full|plist|dict}"; shift 2 ;;
    --ascii)   ASCII=1; shift ;;
    --stdout)  TO_STDOUT=1; shift ;;
    -h|--help) sed -n '4,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "Unknown arg: $1" >&2; exit 2 ;;
    *)         NAME="$1"; shift ;;
  esac
done

case "$FORM" in
  full|plist|dict) ;;
  *) echo "--form must be full, plist or dict" >&2; exit 2 ;;
esac

TMP="$(mktemp -t mdm-payload)"
trap 'rm -f "$TMP"' EXIT

case "$NAME" in
  verify) SRC="$MDM_DIR/jamf-app-config-verify.xml" ;;
  kiosk)  SRC="$MDM_DIR/jamf-app-config-kiosk.xml" ;;
  full)   SRC="$MDM_DIR/jamf-app-config.xml" ;;
  probe)
    # Deliberately the least interesting payload that is still observable on screen:
    # one key, ASCII only, no <real>, no nesting. If Jamf rejects this, nothing about
    # the payload's content is at fault.
    cat >"$TMP" <<'PROBE'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>DisplayTitle</key>
  <string>MDM PROBE</string>
</dict>
</plist>
PROBE
    SRC="$TMP"; LABEL="probe"
    ;;
  "") echo "Which payload? verify | kiosk | full | probe | <path>" >&2; exit 2 ;;
  *)  SRC="$NAME" ;;
esac

[[ -f "$SRC" ]] || { echo "No such payload: $SRC" >&2; exit 1; }

# Lint the source first. A malformed authored file and a Jamf rejection look identical
# from the Jamf side, so failing here says which one it is.
plutil -lint "$SRC" >/dev/null || { echo "Source is not a valid plist: $SRC" >&2; exit 1; }

# plutil normalises and strips comments. It also preserves the types the app validates
# strictly: <real> stays real, and Booleans stay <true/> rather than collapsing to
# <integer>1</integer>, which AppConfig rejects on purpose.
plutil -convert xml1 -o "$TMP.canonical" "$SRC"

# Reshaping is done in Python rather than sed: the file path is passed as argv, never on
# stdin, because a heredoc-fed interpreter swallows stdin and silently produces nothing.
CANONICAL="$(python3 "$MDM_DIR/../scripts/lib/reshape_plist.py" "$TMP.canonical" "$FORM" "$ASCII")"
rm -f "$TMP.canonical"

if [[ "$TO_STDOUT" -eq 1 ]]; then
  printf '%s\n' "$CANONICAL"
  exit 0
fi

printf '%s\n' "$CANONICAL" | pbcopy
KEYS="$(printf '%s\n' "$CANONICAL" | grep -cE '^[[:space:]]*<key>' || true)"
echo "Copied ${LABEL:-$(basename "$SRC")} — form=${FORM}$([[ $ASCII -eq 1 ]] && echo ", ascii")."
echo "${KEYS} keys total, comments stripped."
echo "Paste into Jamf Pro > Devices > Mobile Device Apps > <app> > App Configuration."
