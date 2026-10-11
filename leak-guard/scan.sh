#!/usr/bin/env bash
# Leak scanner. Usage: scan.sh [--staged | --stdin NAME | files...]
#   Base patterns:  patterns.txt next to this script (regex only, no plaintext).
#   Extra patterns: file named by $LEAK_EXTRA_FILE (one ERE per line); never printed.
#   Output: only file:line of hits, never the matched content.
#   Exit 0 = clean, 1 = hit(s), >=2 = scanner error (invalid pattern, unreadable file, ...).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pat=$(mktemp); out=$(mktemp); trap 'rm -f "$pat" "$out"' EXIT
grep -vE '^[[:space:]]*(#|$)' "$here/patterns.txt" > "$pat"
if [ -n "${LEAK_EXTRA_FILE:-}" ] && [ -s "$LEAK_EXTRA_FILE" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$LEAK_EXTRA_FILE" >> "$pat" || [ $? -eq 1 ]
fi
# Validate all patterns up front: grep exits 2 on an invalid ERE.
rc=0; grep -qEi -f "$pat" /dev/null 2>/dev/null || rc=$?
if [ "$rc" -ge 2 ]; then echo "::error::leak-guard: invalid pattern (grep rc=$rc)"; exit 2; fi
# g: grep wrapper - rc 0/1 are normal (hit/no hit), rc>=2 aborts the scan.
g() { local r=0; grep "$@" || r=$?; if [ "$r" -ge 2 ]; then echo "::error::leak-guard: grep failed (rc=$r)" >&2; exit 2; fi; return 0; }
case "${1:-}" in
  --staged)
    while IFS= read -r f; do
      git show ":$f" | g -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|$f:|"
    done < <(git diff --cached --name-only --diff-filter=ACMR) > "$out" ;;
  --stdin)
    g -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|${2:-stdin}:|" > "$out" ;;
  *)
    if [ $# -eq 0 ]; then mapfile -t files < <(git ls-files); set -- "${files[@]}"; fi
    if [ $# -gt 0 ]; then g -nEiIH -f "$pat" -- "$@" | cut -d: -f1,2 > "$out"; fi ;;
esac
if [ -s "$out" ]; then
  while IFS= read -r l; do echo "::error file=${l%%:*}::leak pattern hit at $l (content not shown)"; done < "$out"
  echo "leak-guard: $(wc -l < "$out") hit(s)"; exit 1
fi
echo "leak-guard: 0 hits"
