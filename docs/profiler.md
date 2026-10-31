# eider-profiler: design

The profiler has two halves. The **recording** half is in eider-lang: `eiderc build|run|test
--profile[=cpu,mem,conc]` compiles the program with a shadow stack and event hooks and links
the runtime's profiling part (core/eider_prof.c), which samples, counts and writes the profile
file; `std/profile` and packages/http's `http/profiling` control it from inside the program.
Its contract is eider-lang `docs/runtime.md`, "Profiler" (what is recorded, the environment
variables, the file format, the overhead) and `core/RUNTIME.md`, "Profiling". The **reading**
half is this repository: everything that turns a profile into something a person or a CI job
reads, in Eider.

## Why the split

The runtime does only what can't be done later: what must happen in the signal handler (copy
the shadow stack into a ring), at an allocation (count it at its site, remember its size and
site for the free) or a wait (time it), and writing those tables out. Names, demangling,
self/total arithmetic, labels, flame graphs and diffs are analysis: they don't belong in C in
every profiled process, they change more often than the format, and in Eider they are tested
like any other program. The file is the interface, so it is versioned and documented.

## The file, as this tool reads it

JSON lines, format version 1 (eider-lang `docs/runtime.md`, "Profile format"). `prof_model.ei`
reads every line with packages/json, keeps the records it knows and ignores the others, so a
newer runtime that adds a record kind or a field still reads; a header with a higher
`eider_prof` is refused with a message.

- `fn` ids index `names`; a name is the compiler's (`bytes__0std__append`) and is shown as
  its module writes it (`bytes.append`): `<module>__0<package>[_s<path>]__` and
  `<module>__` become `<module>.`.
- `stack` frames are outermost first; the innermost frame's function gets the **self**
  weight, every distinct function on the stack the **total** (once per stack, so recursion
  isn't counted twice). Function 4294967295 first is "[truncated]" (the runtime keeps the
  innermost 128 frames), 0 is "[runtime]" (no Eider frame: a thread that hasn't entered
  Eider code yet).
- a label id names a node of a tree (`parent`, `key`, `value`); a stack's labels are its node
  and the node's ancestors. `--label k=v` keeps stacks whose set has that pair; `--by k`
  groups by the value of k (`(none)` when the set has no k).

## Reports

`report` prints, in order: the header (what was profiled, how long, samples and dropped
samples, threads), top functions by self and by total time, hot lines (innermost positions),
CPU by label (`--by`), allocation sites (count, bytes, live bytes), copy-on-write unshares
(count, bytes copied), `.copy()` calls, List growth and Map rehashes, Drop calls, lock waits
and channel receive waits (count, total, mean), Ref conflicts, spawns, the heap over time
(about ten points of the timeline), and either the leaks at exit (when `main` returned:
`clean_exit`) or the live heap by site (a snapshot of a running program). `--top N` bounds
each table (default 15). `--json` is the same data in one object for scripts.

## Flame graphs

`flame` merges the stacks of each kind into a tree (children by function, so two lines of
one function are one box) and writes one HTML page: the trees as JSON in a
`<script type="application/json">` element (with `<` escaped, so no profile text can end the
script), and about a hundred lines of script that draw the boxes as SVG, root at the top,
width proportional to the weight. Kinds: `cpu` (samples), `alloc` (bytes, from the
allocation stack samples the runtime takes every 512 KiB), `cow` (bytes copied), `lock` and
`recv` (nanoseconds waited). Clicking a box zooms to it, clicking the top box zooms out, the
search box highlights functions matching a regular expression, and colors are a hash of the
module so a module keeps its color across pages. No library, font or request leaves the
file, so it can be attached to a bug or served from a CI artifact as it is.

## Diffs and the regression gate

`diff a b` compares totals, self-time shares by function (matched by name: ids differ
between builds), and bytes allocated and copied by site (`name at file:line`), largest
changes first. `--check` turns it into a gate on the **gated** totals: allocations, bytes
allocated, copy-on-write count and bytes, `.copy()` count, List growth count and bytes, Map
rehash count and bytes, Drop calls. For a deterministic program on a fixed input (the
compiler compiling itself, a benchmark) these are the same on every run, machine and load,
so a tolerance of 0% is meaningful; CPU samples, waits and the peak heap depend on timing
and the machine and are reported, never gated. eider-lang's `scripts/profile-compiler.sh
--save-baseline` / `--check` and `PROFILE=1 scripts/bench.sh` produce the profiles to compare.

## Recording

`record -- prog.ei args` builds `prog.ei` with `--profile` into a scratch directory with
`$EIDERC` (else the toolchain's `target/eiderc-next`, else `eiderc` on the PATH), runs it
with `EIDER_PROF` (and `EIDER_PROF_HZ`, `EIDER_PROF_CLOCK=wall`) set through `env`, removes
the build, and exits with the program's code. For a service, build it with `--profile`
yourself and capture on demand (SIGUSR2, `std/profile.snapshot`, or `/debug/profile`).

## The load generator

`eider-loadgen` (loadgen.ei) exists so a service can be profiled under load with nothing but
Eider: N threads, each with one keep-alive connection from packages/http's client, sending a
mix of requests (`--req "METHOD PATH [BODY]"`, `{n}` a key from `--keys`, `{t}` the thread)
for `--seconds` or `--requests`, then one line with the count, errors, non-2xx answers,
throughput and latency percentiles.

## Tests

`tests/run.sh`: golden outputs of every command on hand-written fixtures (exact formatting,
labels, diff and `--check` exit codes, a future format version); real programs recorded with
`record` whose reports must show their designed hot spots (a CPU-bound function and labels,
copy-on-write and `.copy()` in a loop, a contended Mutex); the flame graph page's script run
in node against a DOM stub; determinism of the gated counts (one program recorded twice
passes `--check` at 0%); and examples/kvstore under eider-loadgen, split by route and by
JSON-RPC method, with live `/debug/profile` and `/debug/heap` captures.
