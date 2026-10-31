#!/bin/sh
# Build target/bin/eider-profiler and target/bin/eider-loadgen.
#
#   scripts/build.sh            fetch dependencies if eider.lock is missing, then build
#
# The toolchain is the eider-lang checkout $EIDER_ROOT, else $EIDER_LANG (default: ../eider-lang next to this
# repository), the one eider.toml's path dependencies point into. The sources import their
# dependencies by package name (`import "json"`, `import "http/client"`), which the compiler
# resolves through eider.lock. Package imports, and `--profile` for `eider-profiler record`,
# need an eiderc newer than eider-lang's seed, so this builds target/eiderc from the
# checkout's compiler/ with its scripts/ei (only a C11 compiler: $CC, default cc) when that is
# missing or older than compiler/, std/ or core/. target/core and target/std link the
# toolchain's, so the binaries find the prelude as eiderc does.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
toolchain=$(cd "${EIDER_ROOT:-${EIDER_LANG:-$here/../eider-lang}}" 2>/dev/null && pwd -P) || { echo "build.sh: set EIDER_ROOT (or EIDER_LANG) to the eider-lang checkout" >&2; exit 2; }
[ -x "$toolchain/scripts/ei" ] || { echo "build.sh: $toolchain is not an eider-lang checkout (no scripts/ei); set EIDER_LANG" >&2; exit 2; }
# the toolchain must be the same major.minor as this tool (VERSION, eider.toml's `eider`)
want=$(sed -n 's/^eider = "\([0-9]*\.[0-9]*\)"$/\1/p' "$here/eider.toml")
if [ ! -f "$toolchain/VERSION" ]; then
  echo "build.sh: $toolchain has no VERSION file; eider-profiler $(cat "$here/VERSION") needs Eider $want.x" >&2; exit 2
fi
have=$(sed -n '1s/^\([0-9]*\.[0-9]*\)\..*/\1/p' "$toolchain/VERSION")
if [ "$have" != "$want" ]; then
  echo "build.sh: the toolchain at $toolchain is Eider $(head -1 "$toolchain/VERSION"), but eider-profiler $(cat "$here/VERSION") goes with Eider $want.x (the same major.minor); use a matching eider-lang or eider-profiler" >&2; exit 2
fi
if [ ! -f "$here/eider.lock" ]; then
  "$toolchain/scripts/eider-pkg" -C "$here" fetch
fi
mkdir -p "$here/target/bin"
eiderc=$here/target/eiderc
if [ ! -x "$eiderc" ] || [ -n "$(find "$toolchain/compiler" "$toolchain/std" "$toolchain/core" \( -name '*.ei' -o -name '*.c' -o -name '*.h' \) -newer "$eiderc" 2>/dev/null | head -1)" ]; then
  EIDER_CACHE=off "$toolchain/scripts/ei" build "$toolchain/compiler/main.ei" -o "$eiderc"
fi
ln -sfn "$toolchain/core" "$here/target/core"
ln -sfn "$toolchain/std" "$here/target/std"
EIDER_ROOT=$toolchain "$eiderc" build "$here/main.ei" -o "$here/target/bin/eider-profiler"
EIDER_ROOT=$toolchain "$eiderc" build "$here/loadgen.ei" -o "$here/target/bin/eider-loadgen"
echo "built $here/target/bin/eider-profiler, eider-loadgen (toolchain $toolchain)"
