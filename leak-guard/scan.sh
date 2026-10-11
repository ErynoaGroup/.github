#!/usr/bin/env bash
# Leak scanner. Usage: scan.sh [--staged | --stdin NAME | files...]
#   Base patterns:  patterns.txt next to this script (regex only, no plaintext).
#   Extra patterns: file named by $LEAK_EXTRA_FILE (one ERE per line); never printed, NEVER allowlisted.
#   Allowlist:      .leak-guard-allow in the scanned (caller) repo root, or $LEAK_ALLOW_FILE.
#                   Only for file/--staged scans of base patterns; never for --stdin (commit messages, PR text).
#                   Entry: <path | narrow glob | path:line:sha256(line)>  # <reason, mandatory>
#                   Must lie under tests/ or fixtures/; '*' only inside the last path segment; no '**', '?', '[]'.
#                   Anything else => exit 2. See README.md.
#   Output: hit COUNT per file only, never lines or content. Allowlisted hits: ::notice count per file + total.
#   Exit 0 = clean, 1 = hit(s), >=2 = scanner error.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
base=$(mktemp); extra=$(mktemp); out=$(mktemp); allow=$(mktemp); acnt=$(mktemp)
trap 'rm -f "$base" "$extra" "$out" "$allow" "$acnt"' EXIT
grep -vE '^[[:space:]]*(#|$)' "$here/patterns.txt" > "$base"
if [ -n "${LEAK_EXTRA_FILE:-}" ] && [ -s "$LEAK_EXTRA_FILE" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$LEAK_EXTRA_FILE" > "$extra" || [ $? -eq 1 ]
fi
for p in "$base" "$extra"; do
  [ -s "$p" ] || continue
  rc=0; grep -qEi -f "$p" /dev/null 2>/dev/null || rc=$?
  if [ "$rc" -ge 2 ]; then echo "::error::leak-guard: invalid pattern (grep rc=$rc)"; exit 2; fi
done
g() { local r=0; grep "$@" || r=$?; if [ "$r" -ge 2 ]; then echo "::error::leak-guard: grep failed (rc=$r)" >&2; exit 2; fi; return 0; }

# --- allowlist (caller repo) -------------------------------------------------
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
af="${LEAK_ALLOW_FILE:-}"
if [ -z "$af" ] && [ -n "$root" ] && [ -f "$root/.leak-guard-allow" ]; then af="$root/.leak-guard-allow"; fi
if [ -n "$af" ] && [ "${1:-}" != "--stdin" ]; then
  [ -f "$af" ] || { echo "::error::leak-guard: allowlist $af not found"; exit 2; }
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    case "$line" in ''|'#'*) continue ;; esac
    entry=${line%%#*}; entry=${entry%"${entry##*[![:space:]]}"}; reason=${line#*#}
    bad() { echo "::error::leak-guard: allowlist line $n: $1"; exit 2; }
    { [ "$entry" != "$line" ] && [ -n "${reason//[[:space:]]/}" ]; } || bad "missing '# reason'"
    path=$entry
    if [[ "$entry" =~ ^(.+):([1-9][0-9]*):([0-9a-f]{64})$ ]]; then path=${BASH_REMATCH[1]}; fi
    case "$path" in tests/*|fixtures/*) ;; *) bad "only paths under tests/ or fixtures/" ;; esac
    case "$path" in *'**'*|*'?'*|*'['*|*']'*|*' '*|*..*|*:*) bad "forbidden glob/char" ;; esac
    dir=${path%/*}; case "$dir" in *'*'*) bad "'*' only in the last path segment" ;; esac
    [ "${path##*/}" != "*" ] || bad "bare '*' too broad"
    printf '%s\n' "$entry" >> "$allow"
  done < "$af"
fi
allowed() { # $1 rel path, $2 line, $3 src (file or :staged)
  local e p sum=""
  while IFS= read -r e; do
    if [[ "$e" =~ ^(.+):([1-9][0-9]*):([0-9a-f]{64})$ ]]; then
      [ "${BASH_REMATCH[1]}" = "$1" ] && [ "${BASH_REMATCH[2]}" = "$2" ] || continue
      [ -n "$sum" ] || sum=$( { if [ "${3:0:1}" = ":" ]; then git show "$3"; else cat -- "$3"; fi; } | sed -n "${2}p" | tr -d '\n' | sha256sum | cut -d' ' -f1)
      [ "$sum" = "${BASH_REMATCH[3]}" ] && return 0
    else
      # '*' must not cross '/': directory part literal, glob only on the last segment
      [ "${1%/*}" = "${e%/*}" ] || continue
      # shellcheck disable=SC2053
      [[ "${1##*/}" == ${e##*/} ]] && return 0
    fi
  done < "$allow"
  return 1
}
# emit SRC REL: base hits filtered by allowlist, extra hits never filtered; prints "rel:line"
emit() {
  local src=$1 rel=$2
  rel=${rel#"$root"/}; rel=${rel#./}
  { if [ "${src:0:1}" = ":" ]; then git show "$src"; else cat -- "$src"; fi; } | g -nEiI -f "$base" | cut -d: -f1 |
    while IFS= read -r l; do if [ -s "$allow" ] && allowed "$rel" "$l" "$src"; then echo "$rel" >> "$acnt"; else echo "$rel:$l"; fi; done
  if [ -s "$extra" ]; then
    { if [ "${src:0:1}" = ":" ]; then git show "$src"; else cat -- "$src"; fi; } | g -nEiI -f "$extra" | cut -d: -f1 | sed "s|^|$rel:|"
  fi
}
case "${1:-}" in
  --staged)
    while IFS= read -r f; do emit ":$f" "$f"; done < <(git diff --cached --name-only --diff-filter=ACMR) > "$out" ;;
  --stdin)
    name=${2:-stdin}; all=$(mktemp); cat "$base" "$extra" > "$all"
    g -nEiI -f "$all" | cut -d: -f1 | sed "s|^|$name:|" > "$out"; rm -f "$all" ;;
  *)
    if [ $# -eq 0 ]; then mapfile -t files < <(git ls-files); set -- "${files[@]}"; fi
    for f in "$@"; do
      { [ -L "$f" ] || [ -d "$f" ]; } && continue          # submodule gitlinks, symlinks
      [ -f "$f" ] || { echo "::error::leak-guard: cannot read $f"; exit 2; }
      emit "$f" "$f"
    done > "$out" ;;
esac
if [ -s "$acnt" ]; then # allowlisted hits: count per file + total, never lines/content
  sort "$acnt" | uniq -c | while read -r c f; do echo "::notice file=$f::$c allowlisted"; done
  echo "leak-guard: $(wc -l < "$acnt") allowlisted hit(s) total"
fi
if [ -s "$out" ]; then
  cut -d: -f1 "$out" | sort | uniq -c | while read -r c f; do echo "::error file=$f::$c leak pattern hit(s) (lines/content not shown)"; done
  echo "leak-guard: $(wc -l < "$out") hit(s)"; exit 1
fi
echo "leak-guard: 0 hits"
