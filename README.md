# eider-profiler

Reports, flame graphs, folded stacks and diffs of the profiles that Eider programs write when
they are built with `eiderc build|run --profile` (eider-lang `docs/runtime.md`, "Profiler").
Written in Eider. Two uses are first-class:

- **the language itself**: the compiler, std and the runtime, where allocation and
  copy-on-write counts are deterministic and can gate regressions;
- **applications such as web services**: cheap enough to leave on, captured on demand from a
  running process, and split per endpoint by labels.

```sh
EIDER_LANG=~/workplace/eider-lang sh scripts/build.sh     # target/bin/eider-profiler, eider-loadgen
target/bin/eider-profiler record -- prog.ei args...      # build with --profile, run, write eider.prof
target/bin/eider-profiler report eider.prof              # tables
target/bin/eider-profiler flame eider.prof -o flame.html # an interactive flame graph
```

## Commands

| Command | What |
|---|---|
| `report <file> [--top N] [--label k=v] [--by key] [--json]` | top functions by self and total time, hot lines, CPU per label value (`--by route`), allocation sites with live bytes, copy-on-write unshares, `.copy()` calls, List growth and Map rehashes, Drop calls, lock and channel waits, spawns, the heap over time, and leaks at exit, with Eider source positions |
| `flame <file> -o out.html [--kind K] [--label k=v]` | one self-contained HTML file (inline SVG and a small script, nothing loaded from the network) with a flame graph per kind: `cpu` (samples), `alloc` (bytes, sampled every 512 KiB), `cow` (bytes copied), `lock` and `recv` (ns waited); click to zoom, search by regex |
| `folded <file> [--kind K] [--label k=v] [--lines]` | Brendan Gregg's folded stacks (`main;f;g 12`), for flamegraph.pl, speedscope, inferno |
| `diff <a> <b> [--top N] [--check] [--tolerance PCT] [--json]` | totals, self time by function, bytes allocated and copy-on-write bytes by site, a against b; `--check` exits 1 when a deterministic count grew by more than PCT percent (default 0) |
| `record [-o file] [--profile=cpu,mem,conc] [--hz N] [--wall] -- <prog.ei> [args...]` | builds the program with `--profile` ($EIDERC, else `$EIDER_LANG/target/eiderc-next`, else `eiderc`), runs it with the arguments and writes the profile (default `eider.prof`); exits with the program's code |

`--json` gives `report` as one JSON object (`summary`, `functions`, `sites_<kind>`, `leaks`,
`by_label`) and `diff` as `{"metrics": [{name, a, b, gated, regressed}]}`.

Reading a report:

- **self** is time with the function innermost, **total** time with it anywhere on the stack.
  A sample is `period_ns` of CPU time (10.1 ms at 99 Hz), or of wall time with
  `EIDER_PROF_CLOCK=wall`.
- Straight-line functions that call nothing have no frame of their own: their time and
  events count for the caller, at the line of the call (as if inlined).
- **Copy-on-write unshares** are the hidden copies of Eider's value semantics: a String, List,
  Map or Box shared by two values and then changed through one of them is copied first. They
  usually mean a value is kept in two places (a copy in a record and a local, a value sent to
  a thread: values are made unique before they cross threads).
- **Leaks at exit** are shown only when `main` returned normally (`clean_exit`); in a snapshot
  of a running program the same table is the live heap by allocation site.

## Profiling the language

In eider-lang:

```sh
sh scripts/profile-compiler.sh                  # eiderc emit-c compiler/main.ei with --profile
                                                # -> target/prof/eiderc.{prof,report.txt,flame.html}
sh scripts/profile-compiler.sh --save-baseline  # on the revision to compare against
sh scripts/profile-compiler.sh --check          # after the change: diff --check against it
PROFILE=1 sh scripts/bench.sh                   # one profile per benchmark (target/bench-prof)
```

The regression check gates only what is deterministic for a deterministic input: allocations,
bytes allocated, copy-on-write unshares and bytes, `.copy()` calls, List growth, Map rehashes,
Drop calls. Time, samples and the peak heap are shown but never gated (they are noisy). It is
optional, not part of eider-lang's `verify.sh` (decision C205 there): a compiler change that
allocates more on purpose is reviewed, not blocked.

What the compiler's own profile showed when this was written (eiderc compiling itself): about
a sixth of its CPU time in `sys.lit` (turning a `str` literal into a `List[u8]` one byte at a
time through the C core, 1.35 M calls, 27 MiB) and `lower.put` (appending to the output),
List growth of the output buffers (`lower.putb`, `lex.run`, `parse.add`: 20 MiB each in a few
hundred doublings), 1.7 M `.copy()` calls (mostly the lexer's and parser's `let x = place.copy()`),
and copy-on-write unshares in `intern.intern` (the interner's table, 0.5 MiB) and the checker's
`lv_loop`. See eider-lang `docs/compiler.md`, "Compile speed".

## Profiling a service

Build the service with `--profile`, then any of:

- **at exit**: stop it (SIGTERM, Ctrl-C): `eider.prof` (or `$EIDER_PROF`) is written.
- **SIGUSR2**: `kill -USR2 <pid>` writes the profile so far, and the service goes on.
- **over HTTP**, opt-in: eider-http's `profiling.mount(inout router, opts)` with
  `opts.enabled = true` adds `GET /debug/profile?seconds=N` (a fresh N-second recording) and
  `GET /debug/heap` (the live heap now). Local host only unless `opts.remote`.
- **labels**: `profiling.label_routes(inout router)` labels every request with `method` and
  `route` (the pattern); `jsonrpc` adds `rpc` (the method). `report --by route` and
  `flame --label route=/kv/:key` split by them. In code: `profile.with_label("job", "resize", || ...)`.

eider-rpc's examples/kvstore does all of it (`KVSTORE_PROFILING=1` turns the endpoints on). With the load
generator in this repository:

```sh
(cd ../eider-rpc && sh scripts/build.sh)           # fetches examples/kvstore's dependencies
EIDER_CACHE=off target/eiderc build ../eider-rpc/examples/kvstore/main.ei --profile -o kvstore
KVSTORE_PROFILING=1 EIDER_PROF=kv.prof ./kvstore 18431 &
target/bin/eider-loadgen --port 18431 --threads 8 --seconds 4 --keys 500 \
  --req 'POST /rpc {"jsonrpc":"2.0","method":"kv.put","params":["k{n}","v{n}"],"id":1}' \
  --req 'POST /rpc {"jsonrpc":"2.0","method":"kv.get","params":["k{n}"],"id":2}' \
  --req 'GET /kv/k{n}'
curl -s 'localhost:18431/debug/profile?seconds=2' -o live.prof   # meanwhile, from another shell
kill -TERM %1                                                     # writes kv.prof
target/bin/eider-profiler report kv.prof --by route
```

`docs/sample-kvstore-report.txt` is such a report. It shows the service's real hot spot:
`sync.Lock[kv.Kv].with` copying the whole store on every request (52 M copy-on-write unshares,
2.4 GiB copied in 4.5 s, half the CPU samples at `std/sync.ei:42`), because the Lock is a one-value channel and a value is made unique
before it crosses threads, so each `send` of the store back into the Lock copies every key
and value that the request's copy still shares.

Overhead (eider-lang `docs/runtime.md`, "Profiler / Overhead"): sampling itself at 99 Hz is
below 1%; the cost is the shadow stack and, with `mem`, counting every allocation. With
`--profile=cpu`, kvstore under load loses 3.6% of its throughput and eiderc (the worst case:
very many tiny calls) runs 44% longer; with everything on, 37% and 72%. Leave
`--profile=cpu` (or `cpu,conc`) on in a service; turn `mem` on to investigate.

## Layout

| File | What |
|---|---|
| `main.ei` | the command line |
| `prof_model.ei` | the profile file (format version 1) read into memory; names, positions, labels |
| `prof_report.ei` | `report` (text and JSON) and `diff` |
| `prof_flame.ei` | `folded` and the flame graph page |
| `prof_text.ei` | tables, sizes, durations, percentages |
| `loadgen.ei` | eider-loadgen, an HTTP load generator on eider-http's client |
| `tests/run.sh` | profiles real programs and checks that the reports show their hot spots |
| `docs/profiler.md` | the design and the file format |

Build needs the eider-lang checkout ($EIDER_LANG, default `../eider-lang`) with a compiler that
knows `--profile`; `scripts/build.sh` builds `target/eiderc` from it.

The dependencies are [eider-json](https://github.com/klxdev/eider-json) and
[eider-http](https://github.com/klxdev/eider-http) 0.1.0, git packages. `scripts/build.sh`
fetches them offline through eider-pkg's `EIDER_PKG_OVERRIDE` (a local checkout standing in
for the repository): `$EIDER_JSON` / `$EIDER_HTTP`, else `../eider-json` and `../eider-http`,
else (json) the toolchain's pinned `vendor/json`. The kvstore load test of `tests/run.sh`
builds eider-rpc's examples/kvstore from its checkout (`$EIDER_RPC`, default `../eider-rpc`)
and is skipped without one.
