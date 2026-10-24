#!/usr/bin/env bash
# check-pins.sh — guard against the class of gap that only CiM (never a manual build) can hit:
# a target's build/test chain calls `./some-script.sh`, but the datax-orin `commit:` the target is
# pinned to PREDATES that script. A manual build runs the live working tree, so it never exercises
# the pin and the rot stays invisible. This cross-checks, for every target, that EVERY `./*.sh` the
# chain invokes actually exists in the effort repo at the pinned commit.
#
# Usage:   scripts/check-pins.sh
#   DATAX_ORIN_DIR=/path/to/datax-orin   (default: /home/cj/jetson/datax-orin; else a temp clone)
# Exit code = number of (target, script) misses. 0 = all pins coherent with their chains.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_CLONE=/home/cj/jetson/datax-orin
BUILDER_SUBDIR=datax-image-builder   # scripts are called from ${{ BUILDER }} == <workspace>/datax-orin/datax-image-builder
# L4T-tree scripts the chains also call (from $L4T_DIR or $L4T_DIR/source), NOT from the effort repo — never pin-checked.
NON_BUILDER="nvbuild.sh apply_binaries.sh flash.sh l4t_flash_prerequisites.sh"

MISS=0; TARGETS=0
TMPCLONE=""
cleanup(){ [ -n "$TMPCLONE" ] && rm -rf "$TMPCLONE"; }
trap cleanup EXIT

resolve_repo(){ # echoes a path to a datax-orin git tree that has the object DB (any checkout)
  local url="$1"
  if [ -n "${DATAX_ORIN_DIR:-}" ] && [ -d "$DATAX_ORIN_DIR/.git" ]; then echo "$DATAX_ORIN_DIR"; return; fi
  if [ -d "$DEFAULT_CLONE/.git" ]; then echo "$DEFAULT_CLONE"; return; fi
  TMPCLONE="$(mktemp -d)"; git clone --quiet --bare "$url" "$TMPCLONE/repo.git" >/dev/null 2>&1 || return 1
  echo "$TMPCLONE/repo.git"
}

for sdk in "$ROOT"/targets/*/sdk.yml; do
  tgt="$(basename "$(dirname "$sdk")")"
  # only targets that pin the datax-orin effort repo
  url="$(awk '/^gits:/{g=1} g&&/url:/{print $2; exit}' "$sdk")"
  case "$url" in *datax-orin*) ;; *) continue ;; esac
  TARGETS=$((TARGETS+1))
  commit="$(awk '/^gits:/{g=1} g&&/commit:/{print $2; exit}' "$sdk")"
  repo="$(resolve_repo "$url")" || { echo "FAIL $tgt: cannot resolve datax-orin repo ($url)"; MISS=$((MISS+1)); continue; }

  # verify the pinned commit is even reachable
  if ! git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null; then
    echo "FAIL $tgt: pinned commit $commit not found in $repo (push it, or fix the pin)"; MISS=$((MISS+1)); continue
  fi

  # collect every ./script.sh referenced in commands blocks, dedup
  scripts="$(grep -oE '\./[A-Za-z0-9_-]+\.sh' "$sdk" | sed 's#^\./##' | sort -u)"
  [ -z "$scripts" ] && { echo "ok   $tgt @ ${commit:0:9}: (no ./scripts called)"; continue; }

  bad=0
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    case " $NON_BUILDER " in *" $s "*) continue ;; esac   # L4T-tree script, not an effort-repo script
    if git -C "$repo" cat-file -e "$commit:$BUILDER_SUBDIR/$s" 2>/dev/null; then
      :
    else
      echo "FAIL $tgt: chain calls ./$s but it is ABSENT at $BUILDER_SUBDIR/$s @ ${commit:0:9}"
      MISS=$((MISS+1)); bad=$((bad+1))
    fi
  done <<< "$scripts"
  [ "$bad" -eq 0 ] && echo "ok   $tgt @ ${commit:0:9}: all builder scripts the chain calls are present"
done

echo "-----------------------------------------------------------------"
if [ "$MISS" -eq 0 ]; then echo "PASS — $TARGETS datax-orin target(s), all pins coherent with their chains"
else echo "FAIL — $MISS missing (target,script) pair(s) across $TARGETS target(s)"; fi
exit "$MISS"
