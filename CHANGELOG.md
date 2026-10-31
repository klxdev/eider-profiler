# Changelog

eider-profiler shares its major.minor version with the Eider toolchain (eider-lang's
`VERSION`) and ships with it; its patch version is its own. `scripts/build.sh` refuses a
toolchain with another major.minor, and `report` and `diff` warn about a profile written by
one.

## 0.1.0

First release, with eider-lang 0.1 (`eiderc build|run|test --profile`, profile format 1).

- `report`: top functions by self and total time, hot lines, CPU by label (`--by`), allocation
  sites with live bytes, copy-on-write unshares, `.copy()` calls, List growth and Map rehashes,
  Drop calls, lock and channel waits, Ref conflicts, spawns, the heap over time, leaks at
  exit; `--top`, `--label`, `--json`.
- `flame`: a self-contained interactive flame graph page (cpu, alloc, cow, lock, recv).
- `folded`: Brendan Gregg's folded stacks, with `--lines` and `--label`.
- `diff`: totals, functions and sites compared; `--check [--tolerance PCT]` gates the
  deterministic counts.
- `record -- prog.ei args`: build with `--profile`, run, write the profile.
- `eider-loadgen`: an HTTP load generator on packages/http's client.
- `--version`.
