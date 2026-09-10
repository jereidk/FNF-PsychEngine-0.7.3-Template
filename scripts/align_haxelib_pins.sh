#!/usr/bin/env bash
# Align every git-pinned clone in .haxelib to its hmm.json ref BEFORE hmm/haxelib
# touch them.
#
# Why: `haxelib git <name> <url> <ref>` on an ALREADY-installed library (cached
# tree, imported export, or warm-cache rerun) goes down haxelib's update() path,
# which is a bare `git pull` inside the clone (haxelib 4.1.1, bundled with
# Haxe 4.3.7 -- Vcs.hx). On an imported/cached tree that pull either:
#   * aborts with "fatal: Need to specify how to reconcile divergent branches"
#     (git >= 2.27 default when branch and upstream diverged), or
#   * fast-forwards the clone PAST its pinned commit, silently breaking
#     reproducibility against the prebuilt ndlls that shipped with the tree.
#
# Fix, per dependency type:
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
# Clean up dev-link (.dev) files from imported trees BEFORE alignment.
# `haxelib git <name> <url> <ref>` on an existing clone may have been
# import"ed" from another repo/export (NV's haxelib-cache-export): the
# cloned .haxelib tree carries a .dev marker whose value is the ABSOLUTE
# checkout path of the EXPORTING runner (e.g.
#   /home/runner/work/NightmareVision-Android-Support/NightmareVision-
#   Android-Support/.haxelib/lime/git
# ).
# haxelib treats that as a "dev dependency" with that path as its
# development directory, so `haxelib run lime config ...` later reads
# haxelib.json from that dead path and fails (Error parsing haxelib.json
# for lime@dev).
#
# Fix: rewrite every .dev inside .haxelib/*/git/ whose value contains a
# path that DOES NOT exist inside this workspace. Replace it with the
# current workspace root. Same rewrite is done on any .haxelib file
# whose content carries a stale /home/runner/work/ or absolute path from
# the export machine.
# ------------------------------------------------------------------
if [ -d .haxelib ]; then
  # Rewrite .dev files whose value points outside the workspace.
  find .haxelib -type f -name .dev -print0 2>/dev/null | while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    val=$(cat "$f")
    case "$val" in
      ""|*/.haxelib/*|${GITHUB_WORKSPACE}*)
        # Already points at this workspace (or empty) -- leave it.
        ;;
      /*)
        # Absolute path from the export machine: replace if it does not
        # live inside the current workspace tree.
        case "$val" in
          ${GITHUB_WORKSPACE}*|${GITHUB_WORKSPACE}/*) ;;
          *)
            # Rewrite to current workspace + same relative remainder.
            rel="${val#/home/runner/work/*/}"
            [ -z "$rel" ] && rel="${val##*/}"
            newval="${GITHUB_WORKSPACE}/${rel}"
            # If the target path would still be wrong (no /home/runner/work/ at all),
            # fall back to the git dep dir itself (the safest known-existing path).
            if [ ! -d "$(dirname "$newval" 2>/dev/null)" ]; then
              newval="${GITHUB_WORKSPACE}/.haxelib/$(basename "$(dirname "$f")")/git"
            fi
            echo "$newval" > "$f"
            echo "Fixed dev path in: $f (was: $val)"
            ;;
        esac
        ;;
      *)
        # Relative/unknown: leave alone.
        ;;
    esac
  done

  # Also rewrite any OTHER file under .haxelib that embeds a stale absolute
  # path (haxelib.json dev links, registry entries, etc.) pointing at the
  # exporting machine's checkout. Only touch files whose path is unreachable.
  find .haxelib -type f \( -name .dev -o -name haxelib.json -o -name .current \) -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      if grep -qE '/home/runner/work/[^/"]+' "$f" 2>/dev/null; then
        # Rewrite /home/runner/work/<repo>/<repo>/<remainder> -> $GITHUB_WORKSPACE/<remainder>
        sed -i -E "s#/home/runner/work/[^/]+/[^/]+#${GITHUB_WORKSPACE}#g" "$f" 2>/dev/null || true
        echo "Rewrote stale path in: $f"
      fi
    done
fi

if [ ! -d .haxelib ]; then
  echo "No .haxelib tree yet -- nothing to align (haxelib will clone from scratch)."
  exit 0
fi

command -v jq >/dev/null || { echo "jq not found -- skipping pin alignment."; exit 0; }

# Git-pinned deps only; haxelib-release deps have nothing to align.
jq -r '.dependencies[] | select(.type=="git") | "\(.name)|\(.ref // "")"' hmm.json |
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
