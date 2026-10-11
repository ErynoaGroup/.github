#!/usr/bin/env bash
# Leak scanner. Usage: scan.sh [--staged | --stdin NAME | files...]
#   Base patterns:  patterns.txt next to this script (regex only, no plaintext).
#   Extra patterns: file named by $LEAK_EXTRA_FILE (one ERE per line); never printed.
#   Output: only file:line of hits, never the matched content.
#   Allowlist:      $LEAK_ALLOW_FILE (default: .leak-guard-allow in the scanned repo root, if present).
#                   Entry: <path>:<line>:<sha256 of the line content without newline>  # <reason, mandatory>
#                   No wildcards. A hit is suppressed only if path, line AND hash match exactly.
#                   Applies to file and --staged scans, not to --stdin. Malformed entry => exit 2.
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
# --- allowlist ---------------------------------------------------------------
allow=$(mktemp); trap 'rm -f "$pat" "$out" "$allow"' EXIT
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
af="${LEAK_ALLOW_FILE:-}"
if [ -z "$af" ] && [ -n "$root" ] && [ -f "$root/.leak-guard-allow" ]; then af="$root/.leak-guard-allow"; fi
if [ -n "$af" ]; then
  [ -f "$af" ] || { echo "::error::leak-guard: allowlist $af not found"; exit 2; }
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    case "$line" in ''|'#'*) continue ;; esac
    entry=${line%%#*}; entry=${entry%"${entry##*[![:space:]]}"}; reason=${line#*#}
    if [ "$entry" = "$line" ] || [ -z "${reason//[[:space:]]/}" ]; then
      echo "::error::leak-guard: allowlist line $n has no '# reason'"; exit 2; fi
    case "$entry" in *'*'*|*'?'*|*'['*|*']'*) echo "::error::leak-guard: allowlist line $n contains a wildcard"; exit 2 ;; esac
    if ! printf '%s' "$entry" | grep -qE '^[^[:space:]]+:[1-9][0-9]*:[0-9a-f]{64}$'; then
      echo "::error::leak-guard: allowlist line $n malformed (path:line:sha256)"; exit 2; fi
    printf '%s\n' "$entry" >> "$allow"
  done < "$af"
fi
# line_of SRC N: content of line N of a file, or of a staged blob when SRC starts with ':'
line_of() { if [ "${1:0:1}" = ":" ]; then git show "$1"; else cat -- "$1"; fi | sed -n "${2}p" | tr -d '\n'; }
filter_allow() { # stdin: path:line hits; drops exact allowlist matches; $1=staged
  if [ ! -s "$allow" ]; then cat; return 0; fi
  while IFS= read -r h; do
    p=${h%:*}; l=${h##*:}; src="$p"; [ "${1:-}" = staged ] && src=":$p"
    sum=$(line_of "$src" "$l" | sha256sum | cut -d' ' -f1)
    rel="$p"; [ -n "$root" ] && rel=${rel#"$root"/}; rel=${rel#./}
    if grep -qxF "$rel:$l:$sum" "$allow"; then echo "leak-guard: allowlisted $rel:$l" >&2; else echo "$h"; fi
  done
}
case "${1:-}" in
  --staged)
    while IFS= read -r f; do
      git show ":$f" | g -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|$f:|"
    done < <(git diff --cached --name-only --diff-filter=ACMR) | filter_allow staged > "$out" ;;
  --stdin)
    g -nEiI -f "$pat" | cut -d: -f1 | sed "s|^|${2:-stdin}:|" > "$out" ;;
  *)
    if [ $# -eq 0 ]; then mapfile -t files < <(git ls-files); set -- "${files[@]}"; fi
    # Skip submodule gitlinks (directories) and symlinks; missing regular files still fail (rc 2).
    keep=(); for f in "$@"; do [ -L "$f" ] || [ -d "$f" ] || keep+=("$f"); done; set -- ${keep[@]+"${keep[@]}"}
    if [ $# -gt 0 ]; then g -nEiIH -f "$pat" -- "$@" | cut -d: -f1,2 | filter_allow > "$out"; fi ;;
esac
if [ -s "$out" ]; then
  while IFS= read -r l; do echo "::error file=${l%%:*}::leak pattern hit at $l (content not shown)"; done < "$out"
  echo "leak-guard: $(wc -l < "$out") hit(s)"; exit 1
fi
echo "leak-guard: 0 hits"
