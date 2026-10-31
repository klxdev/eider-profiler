# Changelog

eider-profiler shares its major.minor version with the Eider toolchain (eider-lang's
`VERSION`) and ships with it; its patch version is its own. `scripts/build.sh` refuses a
toolchain with another major.minor, and `report` and `diff` warn about a profile written by
one.

## 0.1.1

Imports in the dotted form (eider-lang C8.26, issue #91): `import std.bytes`, `import json`,
`import http.client`, and the tool's own modules by its package's name (`import
eider_profiler.prof_model as m` instead of `import "prof_model.ei" as m`), in the sources and
tests/programs.

Needs an Eider 0.1 toolchain whose compiler knows dotted imports (the eider-lang commit after
the next seed). scripts/build.sh builds target/eiderc from the checkout's compiler/, so a
checkout whose compiler/ knows them is enough even before that seed. eider.lock still pins
eider-json and eider-http at their tagged v0.1.0 releases.

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
- `eider-loadgen`: an HTTP load generator on eider-http's client.
- Dependencies: eider-json and eider-http 0.1.0 as git packages (eider-lang keeps only the
  language and its tooling, U19), fetched offline from sibling checkouts or the toolchain's
  vendor/json (`EIDER_PKG_OVERRIDE`); the load test uses eider-rpc's examples/kvstore.
- `--version`.
