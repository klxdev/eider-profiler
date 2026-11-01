# Sourced by scripts/build.sh and tests/run.sh (with `here` set to this repository): the
# Eider toolchain.
#
# The toolchain is the one `eider` (eider-lang's docs/site/tooling/eider.md) picks, the first
# of:
#   1. $EIDER_TOOLCHAIN: a toolchain directory (bin/eiderc) or an eider-lang checkout
#      (scripts/ei), for testing against unreleased work;
#   2. `eider toolchain show --json` here: the installed toolchain for eider.toml's
#      `eider = "MAJOR.MINOR"` (its newest installed patch; else eider's default);
#   3. neither: exit 2, saying to install eider (install.sh).
# Its VERSION must have this tool's MAJOR.MINOR (eider.toml's `eider`; exit 2 otherwise).
#
# Sets toolchain, chosen (why it was picked), theirs (its VERSION), EIDER_TOOLCHAIN and
# EIDER_ROOT (exported, so every later command uses the same one) and EIDERC (the toolchain's
# compiler, which `eider-profiler record` builds with), and defines `ei <args>` and
# `eider_pkg <args>`: the toolchain's compiler and eider-pkg, through `eider` when it is on
# the PATH, else (EIDER_TOOLCHAIN only) the toolchain's own programs.
die() { echo "$(basename "$0"): $*" >&2; exit 2; }
if [ -n "${EIDER_TOOLCHAIN:-}" ]; then
  toolchain=$(cd "$EIDER_TOOLCHAIN" 2>/dev/null && pwd -P) || die "EIDER_TOOLCHAIN=$EIDER_TOOLCHAIN: no such directory"
  chosen="EIDER_TOOLCHAIN"
elif command -v eider >/dev/null 2>&1; then
  shown=$(cd "$here" && eider toolchain show --json 2>/dev/null) || true
  toolchain=$(printf '%s\n' "$shown" | sed -n 's/^{.*"path":"\([^"]*\)".*/\1/p')
  if [ -z "$toolchain" ]; then
    why=$(printf '%s\n' "$shown" | sed -n 's/^{"error":"\(.*\)"}$/\1/p' | sed 's/\\"/"/g')
    die "eider found no toolchain for $here: ${why:-eider toolchain show --json printed \`$shown\`}"
  fi
  chosen="eider toolchain show: $(printf '%s\n' "$shown" | sed -n 's/.*"why":"\(.*\)"}$/\1/p' | sed 's/\\"/"/g')"
else
  die "no Eider toolchain: no \`eider\` on the PATH and no EIDER_TOOLCHAIN; install eider (gh release download --repo klxdev/eider-lang --pattern install.sh && sh install.sh --toolchain; eider-lang's docs/site/tooling/eider.md), or set EIDER_TOOLCHAIN to an Eider toolchain or an eider-lang checkout"
fi
if [ -x "$toolchain/scripts/ei" ] && [ -f "$toolchain/seed/eiderc.c" ]; then
  tc_eiderc=$toolchain/scripts/ei; tc_pkg=$toolchain/scripts/eider-pkg
elif [ -x "$toolchain/bin/eiderc" ]; then
  tc_eiderc=$toolchain/bin/eiderc; tc_pkg=$toolchain/bin/eider-pkg
else
  die "$toolchain ($chosen) is neither an Eider toolchain (bin/eiderc) nor an eider-lang checkout (scripts/ei)"
fi
# the toolchain must be the same major.minor as this tool (VERSION, eider.toml's `eider`)
mine=$(tr -d ' \n' < "$here/VERSION")
want=$(sed -n 's/^eider = "\([0-9]*\.[0-9]*\)"$/\1/p' "$here/eider.toml")
theirs=; [ -f "$toolchain/VERSION" ] && theirs=$(tr -d ' \n' < "$toolchain/VERSION")
[ -n "$theirs" ] || die "the toolchain at $toolchain has no VERSION; eider-profiler $mine needs Eider $want.x"
[ "${theirs%.*}" = "$want" ] || die "the toolchain at $toolchain ($chosen) is Eider $theirs, but eider-profiler $mine goes with Eider $want.x (the same major.minor); \`eider toolchain install $want\`, or use a matching eider-profiler"
EIDER_TOOLCHAIN=$toolchain
EIDER_ROOT=$toolchain
EIDERC=$tc_eiderc
export EIDER_TOOLCHAIN EIDER_ROOT EIDERC
if command -v eider >/dev/null 2>&1; then
  ei() { eider eiderc "$@"; }
  eider_pkg() { eider eider-pkg "$@"; }
else
  ei() { "$tc_eiderc" "$@"; }
  eider_pkg() { "$tc_pkg" "$@"; }
fi
