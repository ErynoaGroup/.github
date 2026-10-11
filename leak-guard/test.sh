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
# --- allowlist (fake values only: "tail"+6 zeros) ----------
z=000000
r=$(mktemp -d); ( cd "$r" && git init -q . ); mkdir -p "$r/tests" "$r/src"
fake="host.tail$z.$(printf ts).net"
printf 'a\n%s\nb\n' "$fake" > "$r/tests/fix.txt"; cp "$r/tests/fix.txt" "$r/src/app.txt"
h=$(sed -n 2p "$r/tests/fix.txt" | tr -d '\n' | sha256sum | cut -d' ' -f1)
scan_in() { ( cd "$r" && "$here/scan.sh" "$@" ); }
al() { printf '%s\n' "$@" > "$r/.leak-guard-allow"; }
al "tests/fix.txt  # fake fixture";                     expect 0 "allow: exact path suppresses" scan_in tests/fix.txt
al "tests/fix*.txt  # fake fixtures";                   expect 0 "allow: narrow glob suppresses" scan_in tests/fix.txt
al "tests/fix.txt:2:$h  # fake fixture";                expect 0 "allow: path:line:hash suppresses" scan_in tests/fix.txt
al "tests/fix.txt";                                     expect 2 "allow: no reason => rc 2" scan_in tests/fix.txt
al "src/app.txt  # outside tests";                      expect 2 "allow: outside tests/ => rc 2" scan_in src/app.txt
al "tests/**  # too broad";                             expect 2 "allow: ** => rc 2" scan_in tests/fix.txt
al "tests/*  # too broad";                              expect 2 "allow: bare * => rc 2" scan_in tests/fix.txt
al "tests/*/fix.txt  # dir glob";                       expect 2 "allow: * in dir => rc 2" scan_in tests/fix.txt
al "tests/fix?.txt  # ?";                               expect 2 "allow: ? => rc 2" scan_in tests/fix.txt
al "tests/fix.txt  # fake fixture";                     expect 1 "allow: other file still hit" scan_in src/app.txt
al "tests/fix.txt:2:$h  # fake fixture"
printf 'a\n%s x\nb\n' "$fake" > "$r/tests/fix.txt";     expect 1 "allow: changed line => hit" scan_in tests/fix.txt
printf 'x\na\n%s\nb\n' "$fake" > "$r/tests/fix.txt";    expect 1 "allow: moved line => hit" scan_in tests/fix.txt
al "tests/fix.txt  # fake fixture"; ex=$(mktemp); printf 'tail%s\n' "$z" > "$ex"
expect 1 "allow: extra-pattern hit never allowlisted" env LEAK_EXTRA_FILE="$ex" bash -c 'cd "$1" && "$2" tests/fix.txt' _ "$r" "$here/scan.sh"
expect 1 "allow: never for --stdin" bash -c 'cd "$1" && printf "%s\n" "$3" | "$2" --stdin msg' _ "$r" "$here/scan.sh" "$fake"
rm -rf "$r" "$ex"
rm -rf "$bad" "$td"; exit $fail
