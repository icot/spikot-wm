# Releasing

A release is a git tag, a GitHub release on `icot/spikot-wm` carrying the arm64 tarball, and a
commit pointing `Formula/spikot-wm.rb` at that tarball. Homebrew users get it with
`brew update && brew upgrade spikot-wm`.

Needs `gh`, logged in with `gh auth login` to an account that can push to `icot/spikot-wm`.

## Steps

1. Bump `spikotVersion` in `Sources/StateCore/Version.swift` in the commit with the change it
   describes, and tag that commit, annotated, as AGENTS.md's Versioning section asks:

   ```bash
   git tag -a v0.32.0 -m "v0.32.0 — what changed"
   make version-check        # the version constant matches the newest tag
   ```

   Every changeset gets a version and a tag, but not every tag needs a GitHub release. Run the
   remaining steps for the tags that should reach Homebrew users.

2. Push the commit and the tag. The release script checks that the tag is on the `github`
   remote, because the release is created from it:

   ```bash
   git push github main v0.32.0
   git push origin main v0.32.0        # sourcehut, and codeberg if it is kept in step
   ```

3. Check, then release:

   ```bash
   Contrib/release.sh --dry-run 0.32.0
   Contrib/release.sh 0.32.0
   ```

   The script refuses a dirty tree, a version constant that does not match, a tag that is not
   HEAD or not on the `github` remote, and a release that already exists. It then runs
   `make dist`, creates the release with the tarball and notes listing the commits since the
   previous tag, and commits the new `url` and `sha256` in `Formula/spikot-wm.rb` as
   `chore(formula): Point the formula at v0.32.0`.

4. Push the formula commit. Until it reaches GitHub, the tap still installs the previous
   release:

   ```bash
   git push github main
   git push origin main
   ```

5. Check the published formula:

   ```bash
   brew update
   brew audit --strict --online icot/spikot-wm/spikot-wm
   brew upgrade spikot-wm
   brew services restart spikot-wm     # brew upgrade does not restart the agent
   spikot-wm doctor
   ```

## Notes

- The formula commit comes after the tag, so a tag never contains the formula that points at
  it. The tap reads the formula from the head of `main`, so that does not matter.
- Pushing the formula commit before the release exists would make `brew install` fail with a
  404, which is why the script commits it but leaves the push to you.
- `THIRD_PARTY_NOTICES.md` names the versions of `swift-argument-parser` and `swift-log`. When
  `Package.resolved` changes them, update the table and the license texts before releasing.
- Release binaries are arm64 only, and `make dist` refuses anything else.
