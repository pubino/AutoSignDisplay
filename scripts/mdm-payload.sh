#!/usr/bin/env bash
set -euo pipefail

# Emit an MDM payload in the canonical form Jamf's App Configuration field accepts,
# and copy it to the clipboard.
#
# The files in mdm/ lead with a long comment block and carry no DOCTYPE, because their
# job is to be read. Jamf validates what you paste and rejects that shape with
# FIELD_CONFIGURATION_PLIST_INCORRECT_FORMAT. Rather than strip the documentation out
# of the source files, convert at paste time: plutil adds the DOCTYPE, drops comments,
# and normalises the whole thing.
#
# Usage (runnable from any directory):
#   ./scripts/mdm-payload.sh verify        # first-install verification
#   ./scripts/mdm-payload.sh kiosk         # locked-down display
#   ./scripts/mdm-payload.sh full          # full reference of every key
#   ./scripts/mdm-payload.sh <path>        # any plist
#
#   --stdout   print instead of copying

MDM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../mdm" && pwd)"
TO_STDOUT=0
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stdout)  TO_STDOUT=1; shift ;;
    -h|--help) sed -n '4,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "Unknown arg: $1" >&2; exit 2 ;;
    *)         NAME="$1"; shift ;;
  esac
done

case "$NAME" in
  verify) SRC="$MDM_DIR/jamf-app-config-verify.xml" ;;
  kiosk)  SRC="$MDM_DIR/jamf-app-config-kiosk.xml" ;;
  full)   SRC="$MDM_DIR/jamf-app-config.xml" ;;
  "")     echo "Which payload? verify | kiosk | full | <path>" >&2; exit 2 ;;
  *)      SRC="$NAME" ;;
esac

[[ -f "$SRC" ]] || { echo "No such payload: $SRC" >&2; exit 1; }

# Lint the source first. A malformed authored file and a Jamf rejection look identical
# from the Jamf side, so failing here says which one it is.
plutil -lint "$SRC" >/dev/null || { echo "Source is not a valid plist: $SRC" >&2; exit 1; }

CANONICAL="$(plutil -convert xml1 -o - "$SRC")"

if [[ "$TO_STDOUT" -eq 1 ]]; then
  printf '%s\n' "$CANONICAL"
  exit 0
fi

printf '%s\n' "$CANONICAL" | pbcopy
KEYS="$(printf '%s\n' "$CANONICAL" | grep -c '^	<key>' || true)"
echo "Copied $(basename "$SRC") to the clipboard — ${KEYS} top-level keys, comments stripped, DOCTYPE added."
echo "Paste into Jamf Pro > Devices > Mobile Device Apps > <app> > App Configuration."
