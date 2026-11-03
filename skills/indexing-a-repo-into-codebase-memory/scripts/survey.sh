#!/usr/bin/env bash
# Survey a repo to decide what a .cbmignore should exclude before a full codebase-memory index.
# Usage: survey.sh <repo-path> [top-n]
set -euo pipefail
repo="${1:?repo path required}"; n="${2:-10}"
cd "$repo"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  list() { git ls-files; }
else
  list() { find . -type f -not -path './.git/*' -not -path '*/node_modules/*' | sed 's|^\./||'; }
fi
total=$(list | wc -l | tr -d ' ')
echo "repo: $(pwd)  tracked files: $total  size: $(du -sh . | cut -f1)"
echo; echo "## top-level dirs (file count)"
list | awk -F/ 'NF>1{print $1}' | sort | uniq -c | sort -rn | head -"$n"
echo; echo "## second-level hotspots (file count)"
list | awk -F/ 'NF>2{print $1"/"$2}' | sort | uniq -c | sort -rn | head -"$n"
echo; echo "## extensions (file count)"
list | awk -F. 'NF>1 && $NF !~ /\//{print "."$NF}' | sort | uniq -c | sort -rn | head -"$n"
echo; echo "## noise candidates by dir (fixtures, snapshots, vendored, generated, bundles, media, lockfiles, data)"
list | grep -E -i '(^|/)(fixtures?|snapshots?|__snapshots__|testdata|test-data|test-models|vendor|third[_-]party|generated|gen|bundles?|web-bundles|dist|build|out|coverage|public|static|assets|media|images?|icons?|\.changeset|\.cursor-plugin)(/|$)|\.(min\.js|min\.css|map|lock|patch|diff|xsd|wsdl|pkl|onnx|bin|wasm|db|sqlite|csv|tsv|parquet|ipynb|png|jpe?g|gif|svg|ico|webp|woff2?|ttf|mp4|mov|pdf|zip|tar|gz|7z)$|lock\.json$' \
  | awk -F/ 'NF>1{print $1"/"$2} NF==1{print $1}' | sort | uniq -c | sort -rn | head -"$n" || true
echo; echo "## largest tracked files (>300K)"
list | tr '\n' '\0' | xargs -0 stat -f '%z %N' 2>/dev/null | awk '$1>300000{printf "%7dK %s\n",$1/1024,$2}' | sort -rn | head -"$n" || true
echo; echo "## dirs that look like duplicated mirrors (same basename tree under 2+ roots)"
list | awk -F/ 'NF>2{print $2}' | sort | uniq -c | awk '$1>20{print $2}' | while read -r b; do roots=$(list | awk -F/ -v b="$b" 'NF>2 && $2==b{print $1}' | sort -u | wc -l | tr -d ' '); [ "$roots" -gt 1 ] && echo "  $b appears under $roots roots"; done || true
echo; echo "## existing ignore files"
for f in .cbmignore .gitignore .codebase-memory.json; do [ -f "$f" ] && { echo "--- $f"; head -40 "$f"; }; done; true
