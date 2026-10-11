#!/usr/bin/env bash
# Self-test for scan.sh. Synthetic samples are assembled at runtime so this file itself stays clean.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); fail=0
expect() { local want=$1 name=$2; shift 2; local rc=0; "$@" >/dev/null 2>&1 || rc=$?; if [ "$rc" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name (rc=$rc, want $want)"; fail=1; fi; }
d="-----"; pem="${d}BEGIN RSA PRIVATE KEY${d}"; pk8="${d}BEGIN PRIVATE KEY${d}"; enc="${d}BEGIN ENCRYPTED PRIVATE KEY${d}"
ula="FD7A:$(printf 115C):A1E0:ab12::1"; ts="host.tail$(printf 'abc123def')"; ts2="x.$(printf 'ts').net"
tsh="host-ts-$(printf 000000)"
for s in "$tsh" "$pem" "$pk8" "$enc" "$ula" "$ts" "$ts2"; do expect 1 "hit: ${s:0:12}…" bash -c 'printf "%s\n" "$1" | "$2" --stdin t' _ "$s" "$here/scan.sh"; done
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
# allowlist counting + '*' must not cross '/'
al "tests/fix.txt  # fake fixture"; printf 'a\n%s\nb\n' "$fake" > "$r/tests/fix.txt"
o=$(scan_in tests/fix.txt 2>&1)
if printf '%s\n' "$o" | grep -qx '::notice file=tests/fix.txt::1 allowlisted' && printf '%s\n' "$o" | grep -q '1 allowlisted hit(s) total'; then echo "ok   allow: notice count + total"; else echo "FAIL allow: notice count + total"; fail=1; fi
printf '%s\n' "$o" | grep -qF "$fake" && { echo "FAIL allow: content leaked in output"; fail=1; } || echo "ok   allow: no content in output"
mkdir -p "$r/tests/sub"; cp "$r/tests/fix.txt" "$r/tests/sub/x.txt"; cp "$r/tests/fix.txt" "$r/tests/fix-a.txt"
al "tests/fix*.txt  # fake fixtures";   expect 1 "allow: glob does not cross /" scan_in tests/sub/x.txt
al "tests/f*  # fake fixtures";         expect 1 "allow: tests/f* not matching tests/sub/..." scan_in tests/sub/x.txt
expect 0 "allow: same-dir glob still suppresses" scan_in tests/fix-a.txt
rm -rf "$r" "$ex"
# --- mentions: digest refs are not @-mentions ----------
hex=$(printf '%064d' 0); hex5=$(printf '%0128d' 0); M="$here/scan.sh"
m() { printf '%s\n' "$1" | "$M" --mentions "ErynoaGroup NiklasJavier"; }
for s in "image@sha256:$hex" "ghcr.io/x/y @sha256:$hex" "img@SHA256:$hex" "img @sha512:$hex5" "(@sha256:$hex)"; do expect 0 "mention: digest ${s:0:16}… no hit" m "$s"; done
expect 1 "mention: @someuser hit" m "hi @someuser"
expect 1 "mention: @someuser next to digest hit" m "img@sha256:$hex cc @someuser"
expect 1 "mention: @sha256user still hit" m "ping @sha256user"
for s in "ping @sha256 x" "ping @sha256-x" "ping @sha256." "ping @sha512 x"; do expect 1 "mention: '${s#ping }' (ohne Doppelpunkt) hit" m "$s"; done
expect 0 "mention: allowed account" m "thanks @NiklasJavier"
expect 0 "mention: code span ignored" m 'see `@someuser`'
rm -rf "$bad" "$td"; exit $fail
