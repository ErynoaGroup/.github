#!/usr/bin/env bash
# Self-test for scan.sh. Synthetic samples are assembled at runtime so this file itself stays clean.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); fail=0
expect() { local want=$1 name=$2; shift 2; local rc=0; "$@" >/dev/null 2>&1 || rc=$?; if [ "$rc" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name (rc=$rc, want $want)"; fail=1; fi; }
d="-----"; pem="${d}BEGIN RSA PRIVATE KEY${d}"; pk8="${d}BEGIN PRIVATE KEY${d}"; enc="${d}BEGIN ENCRYPTED PRIVATE KEY${d}"
ula="FD7A:$(printf 115C):A1E0:ab12::1"; ts="host.tail$(printf 'abc123def')"; ts2="x.$(printf 'ts').net"
for s in "$pem" "$pk8" "$enc" "$ula" "$ts" "$ts2"; do expect 1 "hit: ${s:0:12}…" bash -c 'printf "%s\n" "$1" | "$2" --stdin t' _ "$s" "$here/scan.sh"; done
expect 0 "clean text" bash -c 'printf "hello world\n" | "$1" --stdin t' _ "$here/scan.sh"
bad=$(mktemp); printf '(\n' > "$bad"
expect 2 "broken pattern => rc 2" env LEAK_EXTRA_FILE="$bad" bash -c 'printf "x\n" | "$1" --stdin t' _ "$here/scan.sh"
expect 2 "missing file => rc 2" "$here/scan.sh" /nonexistent-leak-guard-file
td=$(mktemp -d); mkdir "$td/sub"; ln -s /nonexistent "$td/dangling"; printf "ok\n" > "$td/f"
expect 0 "skip dir + dangling symlink" "$here/scan.sh" "$td/sub" "$td/dangling" "$td/f"
# --- allowlist -----------------------------------------------------------
r=$(mktemp -d); ( cd "$r" && git init -q . )
printf 'a\n%s\nb\n' "$ts2" > "$r/fix.txt"
h=$(sed -n 2p "$r/fix.txt" | tr -d '\n' | sha256sum | cut -d' ' -f1)
scan_in() { ( cd "$r" && "$here/scan.sh" fix.txt ); }
printf 'fix.txt:2:%s  # synthetic redaction sample\n' "$h" > "$r/.leak-guard-allow"
expect 0 "allowlist: exact match suppresses" scan_in
printf 'fix.txt:2:%s\n' "$h" > "$r/.leak-guard-allow"
expect 2 "allowlist: entry without reason => rc 2" scan_in
printf 'fix.txt:*:%s  # wildcard\n' "$h" > "$r/.leak-guard-allow"
expect 2 "allowlist: wildcard => rc 2" scan_in
printf '*.txt:2:%s  # wildcard\n' "$h" > "$r/.leak-guard-allow"
expect 2 "allowlist: path glob => rc 2" scan_in
printf 'fix.txt:2:%s  # synthetic redaction sample\n' "$h" > "$r/.leak-guard-allow"
printf 'a\n%s changed\nb\n' "$ts2" > "$r/fix.txt"
expect 1 "allowlist: changed content => hit" scan_in
printf 'x\na\n%s\nb\n' "$ts2" > "$r/fix.txt"
expect 1 "allowlist: moved line => hit" scan_in
rm -rf "$r"
rm -rf "$bad" "$td"; exit $fail
