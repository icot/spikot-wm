#!/bin/bash
# Publishes a GitHub release for an existing tag and points the Homebrew formula at it.
#
#   Contrib/release.sh [--dry-run] <version>        e.g. Contrib/release.sh 0.32.0
#
# Before running it: bump spikotVersion in Sources/StateCore/Version.swift, commit, tag the
# commit v<version>, and push the commit and the tag to the github remote. docs/release.md has
# the whole procedure.
#
# It then builds the tarball with make dist, creates the release with the tarball attached and
# notes listing the commits since the previous tag, and commits the new url and sha256 in
# Formula/spikot-wm.rb. It pushes nothing: the formula commit has to reach the github remote
# after the release exists, since a formula pointing at a missing asset fails to install.
#
# --dry-run checks everything, builds nothing and prints the commands it would run.

set -euo pipefail

repo=icot/spikot-wm
remote=github
formula=Formula/spikot-wm.rb

die() { echo "release.sh: $*" >&2; exit 1; }

dry_run=
if [ "${1:-}" = --dry-run ]; then dry_run=1; shift; fi
[ $# -eq 1 ] || die "usage: Contrib/release.sh [--dry-run] <version>"
version=${1#v}
tag=v$version

cd "$(dirname "$0")/.."

# run <command...>: runs it, or with --dry-run prints it.
run() {
    if [ -n "$dry_run" ]; then
        printf '  would run:'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

# --- checks, all made before anything changes --------------------------------------------

command -v gh >/dev/null || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in; run gh auth login"
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes"

source_version=$(make -s version)
[ "$source_version" = "$version" ] ||
    die "Sources/StateCore/Version.swift says $source_version, not $version"
[ "$(git rev-parse -q --verify "refs/tags/$tag^{commit}")" = "$(git rev-parse HEAD)" ] ||
    die "$tag does not exist or is not HEAD; commit the version bump and tag it first"
make -s version-check >/dev/null

git ls-remote --exit-code --tags "$remote" "refs/tags/$tag" >/dev/null ||
    die "$tag is not on the $remote remote; run: git push $remote main $tag"
! gh release view "$tag" --repo "$repo" >/dev/null 2>&1 ||
    die "a release for $tag already exists on $repo"

previous=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)
name=spikot-wm-$version-macos-arm64
tarball=.build/dist/$name.tar.gz
url=https://github.com/$repo/releases/download/$tag/$name.tar.gz

echo "release $tag of $repo, previous tag ${previous:-none}"

# --- build ---------------------------------------------------------------------------------

if [ -n "$dry_run" ]; then
    run make dist
    sha256="<sha256 of $tarball>"
else
    make dist
    sha256=$(cut -d' ' -f1 "$tarball.sha256")
fi

# --- release -------------------------------------------------------------------------------

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
    echo "## Install"
    echo
    echo '```'
    echo "brew tap icot/spikot-wm https://github.com/icot/spikot-wm"
    echo "brew install spikot-wm"
    echo '```'
    echo
    echo "## Changes${previous:+ since $previous}"
    echo
    git log --format='- %s' ${previous:+"$previous..$tag"}
} > "$notes"
if [ -n "$dry_run" ]; then
    echo "  release notes:"; sed 's/^/    /' "$notes"
fi

run gh release create "$tag" "$tarball" --repo "$repo" --verify-tag \
    --title "spikot-wm $version" --notes-file "$notes"

# --- formula -------------------------------------------------------------------------------

if [ -n "$dry_run" ]; then
    echo "  would set in $formula:"
    echo "    url \"$url\""
    echo "    sha256 \"$sha256\""
    run git commit -m "chore(formula): Point the formula at $tag" -- "$formula"
else
    sed -i '' -E \
        -e "s|^(  url )\".*\"$|\\1\"$url\"|" \
        -e "s|^(  sha256 )\".*\"$|\\1\"$sha256\"|" "$formula"
    grep -q "^  url \"$url\"$" "$formula" && grep -q "^  sha256 \"$sha256\"$" "$formula" ||
        die "could not update url and sha256 in $formula"
    git commit -q -m "chore(formula): Point the formula at $tag" -- "$formula"
fi

echo
echo "Released $tag. Push the formula commit so the tap picks it up:"
echo "  git push $remote main"
