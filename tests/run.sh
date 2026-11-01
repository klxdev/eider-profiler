#!/bin/sh
# eider-profiler's tests.
#
#   sh tests/run.sh             build (scripts/build.sh), then run every test
#   BLESS=1 sh tests/run.sh     rewrite the goldens of the fixture tests (review the diff!)
#   NOBUILD=1 sh tests/run.sh   use the binaries as they are
#   NOLOAD=1 sh tests/run.sh    skip the kvstore load test (it listens on a local port)
#
# 1. fixtures: report, report --json, report --by, folded, diff and diff --check of the
#    hand-checked profile tests/fixtures/small.prof (and small2.prof) equal their goldens.
# 2. real programs, profiled with `record` (tests/programs/*.ei, built with the toolchain's
#    eiderc and --profile), whose reports must show the hot spots they are written to have:
#    cpu.ei (`hot` first by self time, the phase labels), cow_bench.ei (copy-on-write unshares
#    and .copy() in `touch`), mutex.ei (lock waits in `bump`); every flame graph page is
#    self-contained and its script runs (node, when installed); a profile diffed with itself
#    passes --check, and one with more allocations fails it.
# 3. eider-rpc's examples/kvstore (the checkout $EIDER_RPC, default ../eider-rpc; skipped
#    without one) built with --profile under eider-loadgen: the report has the routes and
#    JSON-RPC methods as labels, and /debug/profile and /debug/heap answer a profile.
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
if [ -z "$NOBUILD" ]; then
  sh scripts/build.sh >/dev/null || { echo "FAIL build"; exit 1; }
fi
# the toolchain (scripts/env.sh: EIDER_TOOLCHAIN, else the one `eider` picks), exported with
# EIDER_ROOT and EIDERC, its compiler, which `record` builds with
here=$root
. scripts/env.sh
E=$root/target/bin/eider-profiler
L=$root/target/bin/eider-loadgen
T=$root/target/tests
rm -rf "$T"
mkdir -p "$T"
EIDER_CACHE=off
export EIDER_CACHE
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
# has FILE PATTERN WHAT: FILE has a line matching the extended regex PATTERN
has() { if grep -Eq -- "$2" "$1"; then ok "$3"; else bad "$3 (no /$2/ in $1)"; sed -n 1,40p "$1"; fi; }

# 1. fixtures
F=tests/fixtures
golden() {
  name=$1; shift
  "$E" "$@" > "$T/$name.got" 2>&1
  echo "exit $?" >> "$T/$name.got"
  if [ -n "$BLESS" ]; then cp "$T/$name.got" "$F/$name.out"; fi
  if cmp -s "$T/$name.got" "$F/$name.out"; then ok "fixture $name"; else bad "fixture $name"; diff "$F/$name.out" "$T/$name.got" | head -20; fi
}
golden report report $F/small.prof
golden report_json report $F/small.prof --json --top 3
golden report_by report $F/small.prof --by route --label method=GET
golden folded folded $F/small.prof --lines
golden folded_alloc folded $F/small.prof --kind alloc
golden diff diff $F/small.prof $F/small2.prof --top 5
golden diff_check diff $F/small.prof $F/small2.prof --check --tolerance 5
golden diff_json diff $F/small.prof $F/small2.prof --json
golden bad_version report $F/future.prof
"$E" flame $F/small.prof -o "$T/small.html" && has "$T/small.html" '^<!doctype html>' "flame: the fixture's page"
if grep -Eq '<script [^>]*src=|<link |(src|href)="?https?:' "$T/small.html"; then bad "flame: the page loads nothing from outside"; else ok "flame: the page loads nothing from outside"; fi

# 2. real programs
flame_runs() {
  if ! command -v node >/dev/null; then echo "skip flame script ($1): no node"; return; fi
  if node tests/flame_dom.js "$1" > "$T/flame.log" 2>&1 && grep -q 'rects [1-9]' "$T/flame.log"; then ok "flame script runs ($(basename "$1"): $(cat "$T/flame.log"))"; else bad "flame script ($1)"; cat "$T/flame.log"; fi
}
for p in cpu cow_bench mutex; do
  if ! "$E" record -o "$T/$p.prof" -- "tests/programs/$p.ei" > "$T/$p.out" 2> "$T/$p.err"; then
    bad "record $p"; cat "$T/$p.err"; continue
  fi
  "$E" report "$T/$p.prof" > "$T/$p.report" || bad "report $p"
  "$E" flame "$T/$p.prof" -o "$T/$p.html" || bad "flame $p"
  "$E" folded "$T/$p.prof" > "$T/$p.folded" || bad "folded $p"
done
# cpu: hot is the top function by self time, then warm; the labels split them
sed -n '/^Top functions by self time/,/^$/p' "$T/cpu.report" | sed -n 4p > "$T/cpu.top"
has "$T/cpu.top" ' hot +tests/programs/cpu.ei' "cpu: hot is first by self time"
has "$T/cpu.report" ' warm +tests/programs/cpu.ei' "cpu: warm is in the table"
"$E" report "$T/cpu.prof" --by phase > "$T/cpu.by"
has "$T/cpu.by" '^ +[0-9.]+% +[0-9]+ +hot +hot$' "cpu: --by phase names hot under phase=hot"
"$E" folded "$T/cpu.prof" --label phase=warm > "$T/cpu.warm"
has "$T/cpu.warm" '^main;run;profile.with_label\[i64\];.*warm [0-9]+$' "cpu: folded stacks under phase=warm end in warm"
flame_runs "$T/cpu.html"
# cow_bench: the unshares are in touch, the .copy() calls in touch and clone_all
sed -n '/^Copy-on-write unshares/,/^$/p' "$T/cow_bench.report" | sed -n 4p > "$T/cow.top"
has "$T/cow.top" '^ +3000 +.* touch +tests/programs/cow_bench.ei:15$' "cow_bench: 3000 unshares at touch:15 come first"
has "$T/cow_bench.report" '^ +1000 +.* clone_all +tests/programs/cow_bench.ei:23$' "cow_bench: 1000 .copy() in clone_all"
has "$T/cow_bench.report" '^ +3000 +.* touch +tests/programs/cow_bench.ei:14$' "cow_bench: 3000 .copy() in touch"
has "$T/cow_bench.report" '^none: every allocation was freed$' "cow_bench: no leaks"
flame_runs "$T/cow_bench.html"
# mutex: the waits are on bump's update
sed -n '/^Lock waits/,/^$/p' "$T/mutex.report" | sed -n 4p > "$T/mutex.top"
has "$T/mutex.top" ' bump +tests/programs/mutex.ei:11$' "mutex: the most waited lock is bump's update"
has "$T/mutex.report" '^ +8 +main +tests/programs/mutex.ei:20$' "mutex: 8 spawns in main"
has "$T/mutex.out" '^960$' "mutex: the program's own output"
# diff: a profile against itself passes --check (the counts are deterministic: cow_bench
# recorded twice gives the same ones); cpu against cow_bench (more allocations) fails it
"$E" record -o "$T/cow_bench2.prof" -- tests/programs/cow_bench.ei > /dev/null 2>&1
"$E" diff "$T/cow_bench.prof" "$T/cow_bench2.prof" --check > "$T/d1" && ok "diff --check: the same program recorded twice" || { bad "diff --check: the same program recorded twice"; grep REGRESSION "$T/d1"; }
if "$E" diff "$T/cpu.prof" "$T/cow_bench.prof" --check > "$T/d3"; then bad "diff --check: more allocations fail"; else has "$T/d3" '^REGRESSION allocations: ' "diff --check: more allocations fail"; fi

# 3. kvstore under load: eider-rpc's example, on a copy of its checkout, whose eider.lock is
# fetched there with http and json from their checkouts (as scripts/build.sh takes them)
rpc=${EIDER_RPC:-$root/../eider-rpc}
kv_fetch() {
  mkdir -p "$T/rpc"
  (cd "$rpc" && find . -path ./target -prune -o -path ./.git -prune -o -type f -print) |
    while read -r f; do mkdir -p "$T/rpc/$(dirname "$f")"; cp "$rpc/$f" "$T/rpc/$f"; done
  ov=$EIDER_PKG_OVERRIDE
  for dep in json http; do
    case ",$ov," in *",$dep="*) continue ;; esac
    eval "dir=\${EIDER_$(echo "$dep" | tr 'a-z' 'A-Z'):-}"
    [ -n "$dir" ] || { [ -f "$root/../eider-$dep/eider.toml" ] && dir=$root/../eider-$dep; }
    if [ -z "$dir" ] && [ "$dep" = json ] && [ -f "$toolchain/vendor.lock" ]; then sh "$toolchain/scripts/vendor.sh" fetch json >&2 && dir=$toolchain/.vendor/json; fi
    [ -z "$dir" ] || ov="${ov:+$ov,}$dep=$(cd "$dir" && pwd -P)"
  done
  (EIDER_PKG_OVERRIDE=$ov; export EIDER_PKG_OVERRIDE; eider_pkg -C "$T/rpc/examples/kvstore" fetch)
}
if [ -n "$NOLOAD" ]; then
  echo "skip kvstore load test (NOLOAD)"
elif [ ! -f "$rpc/examples/kvstore/main.ei" ]; then
  echo "skip kvstore load test: no eider-rpc checkout at $rpc (set EIDER_RPC)"
elif ! kv_fetch > "$T/kv.build" 2>&1; then
  bad "fetch eider-rpc's examples/kvstore"; cat "$T/kv.build"
elif ! ei build "$T/rpc/examples/kvstore/main.ei" --profile -o "$T/kvstore" > "$T/kv.build" 2>&1; then
  bad "build eider-rpc's examples/kvstore with --profile"; cat "$T/kv.build"
else
  port=$((20000 + $$ % 20000))
  KVSTORE_PROFILING=1 EIDER_PROF="$T/kv.prof" "$T/kvstore" $port > "$T/kv.log" 2>&1 &
  pid=$!
  sleep 1
  "$L" --port $port --threads 8 --seconds 3 --keys 300 \
    --req 'POST /rpc {"jsonrpc":"2.0","method":"kv.put","params":["k{n}","value-{n}"],"id":1}' \
    --req 'POST /rpc {"jsonrpc":"2.0","method":"kv.get","params":["k{n}"],"id":2}' \
    --req 'GET /kv/k{n}' \
    --req 'GET /health' > "$T/load.out" 2>&1 &
  lpid=$!
  sleep 1
  # a live recording and a heap snapshot while the load runs
  curl -s -o "$T/live.prof" -w '%{http_code}\n' "http://127.0.0.1:$port/debug/profile?seconds=1" > "$T/live.code" 2>/dev/null || echo "no curl" > "$T/live.code"
  curl -s -o "$T/heap.prof" -w '%{http_code}\n' "http://127.0.0.1:$port/debug/heap" > "$T/heap.code" 2>/dev/null || echo "no curl" > "$T/heap.code"
  wait $lpid
  kill -TERM $pid
  wait $pid
  has "$T/load.out" '^requests [1-9][0-9]* errors 0 ' "kvstore: the load ran without errors ($(cat "$T/load.out"))"
  "$E" report "$T/kv.prof" --by route > "$T/kv.report" 2>&1 || bad "kvstore: report"
  has "$T/kv.report" '^ +[0-9.]+% +[0-9]+ +/rpc ' "kvstore: CPU per route has /rpc"
  has "$T/kv.report" '^ +[0-9.]+% +[0-9]+ +/kv/:key ' "kvstore: CPU per route has /kv/:key"
  "$E" report "$T/kv.prof" --by rpc > "$T/kv.rpc" 2>&1
  has "$T/kv.rpc" '^ +[0-9.]+% +[0-9]+ +kv.get ' "kvstore: CPU per JSON-RPC method has kv.get"
  has "$T/kv.report" 'Lock\[kv.Kv\]' "kvstore: the store's Lock is in the report"
  if grep -q '^no curl' "$T/live.code"; then
    echo "skip /debug/profile: no curl"
  else
    has "$T/live.code" '^200$' "kvstore: /debug/profile?seconds=1 answers 200"
    "$E" report "$T/live.prof" > "$T/live.report" 2>&1 && ok "kvstore: /debug/profile's answer is a profile" || bad "kvstore: /debug/profile's answer is a profile"
    has "$T/heap.code" '^200$' "kvstore: /debug/heap answers 200"
    has "$T/heap.prof" '"reason":"snapshot"' "kvstore: /debug/heap's answer is a snapshot"
  fi
fi
[ $fail = 0 ] && echo "ALL OK"
exit $fail
