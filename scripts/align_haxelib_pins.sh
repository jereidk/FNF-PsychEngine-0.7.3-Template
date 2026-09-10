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
