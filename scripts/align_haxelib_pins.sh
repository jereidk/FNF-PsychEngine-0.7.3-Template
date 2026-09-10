#!/usr/bin/env bash
# Align every git-pinned clone in .haxelib to its hmm.json ref BEFORE hmm/haxelib
# touch them, and neutralize stale dev-link (.dev) paths from imported trees so
# haxelib does not try to read haxelib.json from a dead runner checkout.
#
# Why the .dev step exists: when an .haxelib tree is imported from another repo's
# export (e.g. NightmareVision's haxelib-cache-export), each git dep's .dev file
# carries the ABSOLUTE checkout path of the exporting runner. haxelib treats that
# as a dev dependency and later tools like `haxelib run lime config` read
# haxelib.json from that dead path, failing with "Error parsing haxelib.json for
# lime@dev".
#
# Worse: haxelib's own `haxelib git <name> <url> <ref>` can reintroduce that
# stale path when it updates an already-installed clone, so the cleanup has to run
# BOTH before hmm install AND again after it (the caller does the after-pass).
#
# Pin alignment (for context, kept from the prior version):
#   * SHA pins (40 hex chars): fetch + checkout the pin on a dedicated branch
#     whose upstream points at THIS local clone (branch.<name>.remote = .), so
#     haxelib's later `git pull` merges an identical ref -- a guaranteed no-op.
#   * branch pins: hard-reset the branch onto origin/<branch>, so the pull is
#     an ordinary fast-forward to tip.
#
# Libraries not present in .haxelib are skipped (haxelib clones them fresh).
# Per-library failures are warnings, never fatal: hmm install still runs after.

set -u

git config --global pull.rebase false 2>/dev/null || true
git config --global user.email "ci@build.local" 2>/dev/null || true
git config --global user.name "CI" 2>/dev/null || true

# ------------------------------------------------------------------
# Portable find helper: avoid GNU-only `find -print0`/`read -d ''` because
# the macOS runner uses BSD find (no -print0) and this may run under dash.
# haxelib tree paths never contain newlines, so newline-delimited `find`
# output is safe here.
# ------------------------------------------------------------------
# NOTE: these helpers use POSIX sh (no `local`) so they run under dash/bash/ash.

rewrite_dev_file() {
  __agp_f="$1"
  __agp_workspace="${GITHUB_WORKSPACE:-}"
  __agp_newhome="${2:-}"

  __agp_val=$(head -n1 "$__agp_f" 2>/dev/null || true)
  [ -n "$__agp_val" ] || return 0

  # Already points at this workspace (or newhome) -- leave it alone.
  # Only treat as "already clean" when the value STARTS with the known
  # workspace root (or newhome if provided). A path that merely contains
  # /.haxelib/ is NOT guaranteed to point at this checkout.
  case "$__agp_val" in
    ""|"${__agp_workspace}"|"${__agp_workspace}"/*)
      return 0
      ;;
  esac
  if [ -n "${__agp_newhome:-}" ]; then
    case "$__agp_val" in
      ""|"${__agp_newhome}"|"${__agp_newhome}"/*)
        return 0
        ;;
    esac
  fi

  # Absolute path from another machine. Rewrite to the current workspace.
  case "$__agp_val" in
    /*)
      __agp_rewritten=false

      # Prefer: map a /home/runner/work/<repo>/<repo>/<rest> export path to
      # $GITHUB_WORKSPACE/<rest> (matches NV's export layout). Try the
      # documented scheduler layout first, then fall back to any two-segment
      # /home/runner/work/<x>/<y> prefix in case the export came from a
      # self-hosted or differently-nested runner.
      __agp_rest="${__agp_val#/home/runner/work/}"
      if [ "$__agp_rest" != "$__agp_val" ]; then
        # rest = <repo>/<repo>/<rest...>  (may be more than two segments if the
        # export came from a differently-nested checkout). Strip exactly two
        # segments, then use whatever remains.
        __agp_rest="${__agp_rest#*/}"
        __agp_rest="${__agp_rest#*/}"
        __agp_candidate="${__agp_workspace}/${__agp_rest}"
        if [ -d "$(dirname "$__agp_candidate" 2>/dev/null)" ]; then
          echo "$__agp_candidate" > "$__agp_f"
          __agp_rewritten=true
          echo "Fixed dev path in: $__agp_f (was: $__agp_val)"
        fi
      fi

      if [ "$__agp_rewritten" = false ]; then
        # Fallback: rewrite the /home/runner/work/<x>/<y> prefix to the
        # workspace root, preserving everything after the second segment.
        __agp_runnerpath="${__agp_val#/home/runner/work/}"
        if [ "$__agp_runnerpath" != "$__agp_val" ]; then
          __agp_runnerpath="${__agp_runnerpath#*/}"
          __agp_after="${__agp_runnerpath#*/}"
          # after may be empty if the export path was exactly
          # /home/runner/work/<x>/<y> with nothing after; in that case default
          # to the git dep dir itself (known to exist).
          if [ -n "${__agp_after:-}" ]; then
            __agp_candidate="${__agp_workspace}/${__agp_after}"
          else
            __agp_parentdir=$(dirname "$__agp_f" 2>/dev/null || true)
            __agp_libname=$(basename "$__agp_parentdir" 2>/dev/null || true)
            __agp_candidate="${__agp_workspace}/.haxelib/${__agp_libname}/git"
          fi
          if [ -d "$(dirname "$__agp_candidate" 2>/dev/null)" ]; then
            echo "$__agp_candidate" > "$__agp_f"
            __agp_rewritten=true
            echo "Fixed dev path in: $__agp_f (was: $__agp_val) via runner fallback"
          fi
        fi
      fi

      # Last resort: if we could not map the NV-style path, point the .dev at
      # the git dep dir itself. That dir exists whenever the dep is installed,
      # and it is the least-surprising usable path for haxelib's dev-link
      # machinery (it still points at a real checkout, just not at the export
      # machine's absolute path).
      if [ "$__agp_rewritten" = false ]; then
        __agp_parentdir=$(dirname "$__agp_f" 2>/dev/null || true)
        __agp_libname=$(basename "$__agp_parentdir" 2>/dev/null || true)
        if [ -n "${__agp_newhome:-}" ]; then
          __agp_candidate="${__agp_newhome}/.haxelib/${__agp_libname}/git"
        else
          __agp_candidate="${__agp_workspace}/.haxelib/${__agp_libname}/git"
        fi
        if [ -d "$(dirname "$__agp_candidate" 2>/dev/null)" ]; then
          echo "$__agp_candidate" > "$__agp_f"
          __agp_rewritten=true
          echo "Fixed dev path in: $__agp_f (was: $__agp_val) via dep-dir fallback"
        fi
      fi

      return 0
      ;;

    *)
      # Relative/unknown value -- leave it alone.
      return 0
      ;;
  esac
}

rewrite_stale_path_in_file() {
  __agp_f="$1"
  __agp_workspace="${GITHUB_WORKSPACE:-}"

  [ -n "${__agp_workspace:-}" ] || return 0
  [ -f "$__agp_f" ] || return 0

  # Only touch files that actually embed a stale scheduler path. We use sed
  # with a temp file because BSD sed -i often needs an extension and we do not
  # want to assume one; a failed sed is not fatal, we just keep the original.
  if grep -qE '/home/runner/work/[^/"]+' "$__agp_f" 2>/dev/null; then
    __agp_tmp="${__agp_f}.aligntmp.$$"
    if sed -E "s#/home/runner/work/[^/]+/[^/]+#${__agp_workspace}#g" "$__agp_f" > "$__agp_tmp" 2>/dev/null; then
      mv "$__agp_tmp" "$__agp_f"
      echo "Rewrote stale scheduler path in: $__agp_f"
    else
      rm -f "$__agp_tmp"
    fi
  fi
}

# ------------------------------------------------------------------
# Run once now (before pins) to neutralize any imported tree. The caller may
# also run this function a second time AFTER hmm install if it wants to clean
# up any .dev paths haxelib reintroduced.
# ------------------------------------------------------------------
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d .haxelib ]; then
  for f in $(find .haxelib -type f -name .dev 2>/dev/null); do
    [ -f "$f" ] || continue
    rewrite_dev_file "$f"
  done

  for f in $(find .haxelib -type f \( -name haxelib.json -o -name .current \) 2>/dev/null); do
    [ -f "$f" ] || continue
    rewrite_stale_path_in_file "$f"
  done
fi

if [ ! -d .haxelib ]; then
  echo "No .haxelib tree yet -- nothing to align (haxelib will clone from scratch)."
  exit 0
fi

# ------------------------------------------------------------------
# Git-pinned deps only; haxelib-release deps have nothing to align.
# ------------------------------------------------------------------
command -v jq >/dev/null || { echo "jq not found -- skipping pin alignment."; exit 0; }

jq -r '.dependencies[] | select(.type=="git") | "\(.name)|\(.ref)"' hmm.json |
while IFS='|' read -r lib ref; do
  [ -n "$ref" ] || continue
  dir=".haxelib/$lib/git"
  [ -d "$dir" ] || continue
  (
    cd "$dir" || exit 1
    if ! git fetch --depth=1 origin "$ref" 2>/dev/null; then
      # Shallow clone may lack the pinned object; widen once, then retry.
      git fetch --unshallow origin 2>/dev/null || git fetch origin || exit 1
      git fetch --depth=1 origin "$ref" 2>/dev/null || git fetch origin "$ref" || exit 1
    fi
    if [ "${#ref}" -eq 40 ]; then
      # SHA pin: exact checkout + LOCAL upstream => `git pull` is a no-op.
      git checkout -f -B "pin-$lib" "$(git rev-parse "$ref")" || exit 1
      git config "branch.pin-$lib.remote" .
      git config "branch.pin-$lib.merge" "refs/heads/pin-$lib"
    else
      # Branch pin: hard-reset onto upstream so the pull is a fast-forward.
      git checkout -f -B "$ref" "origin/$ref" || exit 1
    fi
    echo "Aligned $lib -> $ref at $(git rev-parse --short HEAD)"
  ) || echo "WARN: could not align $lib to $ref -- leaving clone as imported"
done
