# Changelog

eider-profiler shares its major.minor version with the Eider toolchain (eider-lang's
`VERSION`) and ships with it; its patch version is its own. `scripts/build.sh` refuses a
toolchain with another major.minor, and `report` and `diff` warn about a profile written by
one.

## 0.6.0

For Eider 0.6 (`eider = "0.6"`). Requires eider-http and eider-json 0.6.0.

For tasks (eider-lang 0.6, issue 14): `report` has tables for the descriptor, timer, parker and
join waits of tasks (sites of the new kinds `fd`, `sleep`, `park`, `join`) and for the tasks that
ended, by the site that spawned them (kind `task`: count and time from spawn to end); `--json` has
`<kind>_count` and `sites_<kind>` for them. tests/programs/tasks.ei is the check.

## 0.5.0

For Eider 0.5 (`eider = "0.5"`). Requires eider-http and eider-json 0.5.0. Nothing else changed.

## 0.4.0

For Eider 0.4 (`eider = "0.4"`). Requires eider-http and eider-json 0.4.0; the package version in eider.toml, left at 0.2.0 by the last release, is 0.4.0. Nothing else changed.

## 0.3.0

For Eider 0.3 (`eider = "0.3"`): every plain string literal interpolates (eider-lang U29), so
the literals with braces here are raw strings or have their braces doubled. Requires eider-http and eider-json 0.3.0.

The grant to eider-http adds `fs`: what its modules use (eider-lang #135).

## 0.2.0

For Eider 0.2 (`eider = "0.2"`): eider-lang's 0.2 builds programs only through LLVM (clang
17 or newer; U23) and bootstraps the compiler from a WebAssembly seed (seed/eiderc.wasm; U24).
scripts/env.sh recognises such a checkout (seed/eiderc.wasm, or seed/eiderc.c before).
Nothing else changed.

## 0.1.2

Builds and tests with the toolchain `eider` picks (eider-lang#133) instead of a fixed
eider-lang checkout. scripts/env.sh (sourced by scripts/build.sh and tests/run.sh) takes
`$EIDER_TOOLCHAIN` (a toolchain directory or an eider-lang checkout), else the toolchain
`eider toolchain show --json` names for `eider = "0.1"`, else stops with exit 2 and says to
install `eider`. Both binaries are built with that toolchain's compiler (through `eider`, or
directly when `eider` is not on the PATH) rather than a target/eiderc built from the
checkout's compiler/main.ei, and tests/run.sh records with it (`EIDERC`). `EIDER_ROOT` and
`EIDER_LANG` no longer choose the toolchain for the scripts. Tested with the released Eider
0.1.0 and with eider-lang main. No change to the tool's behaviour.

## 0.1.1

Imports in the dotted form (eider-lang C8.26, issue #91): `import std.bytes`, `import json`,
`import http.client`, and the tool's own modules by its package's name (`import
eider_profiler.prof_model as m` instead of `import "prof_model.ei" as m`), in the sources and
tests/programs.

Needs an Eider 0.1 toolchain whose compiler knows dotted imports (the eider-lang commit after
the next seed). scripts/build.sh builds target/eiderc from the checkout's compiler/, so a
checkout whose compiler/ knows them is enough even before that seed. eider.toml requires, and
eider.lock pins, eider-json and eider-http at their tagged v0.1.1 releases.

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
