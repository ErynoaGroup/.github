#!/usr/bin/env bash
# Self-test for scan.sh. Synthetic samples are assembled at runtime so this file itself stays clean.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); fail=0
expect() { local want=$1 name=$2; shift 2; local rc=0; "$@" >/dev/null 2>&1 || rc=$?; if [ "$rc" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name (rc=$rc, want $want)"; fail=1; fi; }
d="-----"; pem="${d}BEGIN RSA PRIVATE KEY${d}"; pk8="${d}BEGIN PRIVATE KEY${d}"; enc="${d}BEGIN ENCRYPTED PRIVATE KEY${d}"
ula="FD7A:115C:A1E0:ab12::1"; ts="host.tail$(printf 'abc123def')"; ts2="x.$(printf 'ts').net"
for s in "$pem" "$pk8" "$enc" "$ula" "$ts" "$ts2"; do expect 1 "hit: ${s:0:12}…" bash -c 'printf "%s\n" "$1" | "$2" --stdin t' _ "$s" "$here/scan.sh"; done
expect 0 "clean text" bash -c 'printf "hello world\n" | "$1" --stdin t' _ "$here/scan.sh"
bad=$(mktemp); printf '(\n' > "$bad"
expect 2 "broken pattern => rc 2" env LEAK_EXTRA_FILE="$bad" bash -c 'printf "x\n" | "$1" --stdin t' _ "$here/scan.sh"
expect 2 "missing file => rc 2" "$here/scan.sh" /nonexistent-leak-guard-file
rm -f "$bad"; exit $fail
