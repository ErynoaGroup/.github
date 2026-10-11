#!/usr/bin/env bash
# Leak scanner. Usage: scan.sh [--staged | --stdin NAME | files...]
#   Base patterns:  patterns.txt next to this script (regex only, no plaintext).
#   Extra patterns: file named by $LEAK_EXTRA_FILE (one ERE per line); never printed.
#   Output: only file:line of hits, never the matched content. Exit 1 on any hit.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pat=$(mktemp); out=$(mktemp); trap 'rm -f "$pat" "$out"' EXIT
grep -vE '^[[:space:]]*(#|$)' "$here/patterns.txt" > "$pat"
if [ -n "${LEAK_EXTRA_FILE:-}" ] && [ -s "$LEAK_EXTRA_FILE" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$LEAK_EXTRA_FILE" >> "$pat" || true
fi
case "${1:-}" in
  --staged)
    git diff --cached --name-only --diff-filter=ACMR | while IFS= read -r f; do
      git show ":$f" 2>/dev/null | grep -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|$f:|" || true
    done > "$out" ;;
  --stdin)
    grep -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|${2:-stdin}:|" > "$out" || true ;;
  *)
    if [ $# -eq 0 ]; then mapfile -t files < <(git ls-files); set -- "${files[@]}"; fi
    [ $# -gt 0 ] && { grep -nEiIH -f "$pat" -- "$@" 2>/dev/null | cut -d: -f1,2 > "$out" || true; } ;;
esac
if [ -s "$out" ]; then
  while IFS= read -r l; do echo "::error file=${l%%:*}::leak pattern hit at $l (content not shown)"; done < "$out"
  echo "leak-guard: $(wc -l < "$out") hit(s)"; exit 1
fi
echo "leak-guard: 0 hits"
