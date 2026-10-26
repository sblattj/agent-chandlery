#!/usr/bin/env bash
# narr.sh new <dir>                       scaffold page.html + narr.css into <dir>
# narr.sh crop <in.png> <out.png> <w> <h> crop top-left w x h px (CSS px of #shot) and write out.png
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  new) d="${2:?dir}"; mkdir -p "$d"; cp -n "$S/template/narr.css" "$d/" || true
       f="$d/${3:-page}.html"; [[ -e "$f" ]] || cp "$S/template/page.html" "$f"; echo "$f";;
  crop) [[ -x "$S/crop" && "$S/crop" -nt "$S/crop.swift" ]] || swiftc -O "$S/crop.swift" -o "$S/crop"
        mkdir -p "$(dirname "$3")"; "$S/crop" "$2" "$3" "${4:?w}" "${5:?h}";;
  *) sed -n 2,3p "$0"; exit 1;;
esac
