#!/usr/bin/env python3
"""Reshape a canonical XML plist for MDM consoles that reject some wrappers.

Jamf's App Configuration field rejects payloads with
FIELD_CONFIGURATION_PLIST_INCORRECT_FORMAT, and which shapes it objects to is neither
documented nor stable across versions. Two candidates come up repeatedly:

  - The DOCTYPE. Many XML parsers refuse a DOCTYPE outright as XXE mitigation, so
    *adding* one to satisfy a validator can be what trips it.
  - The wrapper. Some consoles want the <dict> alone and treat <plist> as noise.

So this emits whichever shape is asked for, rather than betting on one.

Usage: reshape_plist.py <file> <full|plist|dict> <0|1 ascii>
"""

import re
import sys
import unicodedata

# Characters that arrive by way of a text editor and have no business in a payload that
# has to survive an unknown web form's encoding handling. The em dash in DisplayTitle is
# the one this project actually ships.
TRANSLITERATIONS = {
    "—": "--",   # em dash
    "–": "-",    # en dash
    "‘": "'", "’": "'",
    "“": '"', "”": '"',
    " ": " ",    # non-breaking space
}


def to_ascii(text):
    for source, replacement in TRANSLITERATIONS.items():
        text = text.replace(source, replacement)
    # Anything left that is non-ASCII gets decomposed and stripped rather than silently
    # surviving into a field whose encoding behaviour is unknown.
    decomposed = unicodedata.normalize("NFKD", text)
    return decomposed.encode("ascii", "ignore").decode("ascii")


def reshape(text, form):
    if form == "full":
        return text

    without_doctype = re.sub(r"^<!DOCTYPE[^>]*>\n?", "", text, flags=re.MULTILINE)
    if form == "plist":
        return without_doctype

    # dict: strip the XML declaration and the <plist> wrapper, leaving the root dict.
    body = re.sub(r"^<\?xml[^>]*\?>\n?", "", without_doctype, flags=re.MULTILINE)
    body = re.sub(r"^<plist[^>]*>\n?", "", body, flags=re.MULTILINE)
    body = re.sub(r"\n?</plist>\s*$", "", body)
    return body.strip()


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().splitlines()[-1])

    path, form, ascii_flag = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()

    text = reshape(text, form)
    if ascii_flag:
        text = to_ascii(text)

    sys.stdout.write(text.rstrip("\n") + "\n")


if __name__ == "__main__":
    main()
