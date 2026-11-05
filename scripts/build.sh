#!/bin/sh
# Build target/bin/eider-profiler and target/bin/eider-loadgen.
#
#   scripts/build.sh            fetch the dependencies (eider-pkg fetch), then build
#
# The toolchain is the one scripts/env.sh finds: $EIDER_TOOLCHAIN, else the one `eider` picks
# for this repository (eider.toml's `eider`). The dependencies, eider-json and eider-http, are
# git packages (eider.toml); offline, eider-pkg takes each from a local directory
# (EIDER_PKG_OVERRIDE, eider-lang's docs/site/tooling/eider-pkg.md): $EIDER_JSON / $EIDER_HTTP,
# else the checkouts ../eider-json and ../eider-http, else (json, when the toolchain is an
# eider-lang checkout) its pinned release .vendor/json (fetched there and hash-checked with
# its scripts/vendor.sh); one with none of these is fetched from GitHub. The sources import
# them by package name (`import json`, `import http.client`), which the compiler resolves
# through eider.lock. The toolchain's compiler builds both binaries (`eider build`).
# target/core and target/std link the toolchain's, so the binaries find the prelude as
# eiderc does.
set -e
here=$(cd "$(dirname "$0")/.." && pwd -P)
. "$here/scripts/env.sh"
for dep in json http logging; do
  case ",$EIDER_PKG_OVERRIDE," in *",$dep="*) continue ;; esac
  eval "dir=\${EIDER_$(echo "$dep" | tr 'a-z' 'A-Z'):-}"
  [ -n "$dir" ] || { [ -f "$here/../eider-$dep/eider.toml" ] && dir=$here/../eider-$dep; }
  if [ -z "$dir" ] && [ "$dep" = json ] && [ -f "$toolchain/vendor.lock" ]; then sh "$toolchain/scripts/vendor.sh" fetch json >&2 && dir=$toolchain/.vendor/json; fi
  [ -z "$dir" ] || EIDER_PKG_OVERRIDE="${EIDER_PKG_OVERRIDE:+$EIDER_PKG_OVERRIDE,}$dep=$(cd "$dir" && pwd -P)"
done
export EIDER_PKG_OVERRIDE
eider_pkg -C "$here" fetch > /dev/null
mkdir -p "$here/target/bin"
ln -sfn "$toolchain/core" "$here/target/core"
ln -sfn "$toolchain/std" "$here/target/std"
ei build "$here/main.ei" -o "$here/target/bin/eider-profiler"
ei build "$here/loadgen.ei" -o "$here/target/bin/eider-loadgen"
echo "built $here/target/bin/eider-profiler, eider-loadgen (Eider $theirs at $toolchain; $chosen)"
