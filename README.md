# krita-nightly

Nightly GitHub Actions pipeline that:

1. Checks Krita upstream (`invent.kde.org/graphics/krita.git`) once per night.
2. Skips work when the latest commit already has a release.
3. Builds a forked AUR package (`krita-nightly-bin`) from `krita-git`.
4. Publishes package artifacts (`.pkg.tar.zst`) as a GitHub Release.

## How it works

- `scripts/detect-upstream-commit.sh`
  - resolves upstream `HEAD`
  - computes tag `krita-nightly-bin-<short_commit>`
  - skips build if this release tag already exists
- `scripts/build-krita-aur.sh`
  - runs in Arch Linux
  - installs `paru` to satisfy AUR-only dependencies (for example `kseexpr-qt6-git`)
  - clones `krita-git` AUR packaging and rewrites `pkgname` to `krita-nightly-bin`
  - pins upstream source to the detected commit
  - builds package and emits release notes
- `.github/workflows/nightly-krita-nightly-bin.yml`
  - scheduled nightly + manual dispatch
  - conditionally builds only when a new upstream commit is found
  - creates a GitHub release with generated package files

## Repository setup

1. Push this repository to GitHub.
2. In repository settings, keep `GITHUB_TOKEN` with `contents: write` allowed for workflows.
3. Optionally adjust schedule in `.github/workflows/nightly-krita-nightly-bin.yml`.
4. Trigger `workflow_dispatch` once to verify end-to-end.

## Notes

- The package naming is intentionally forked to `krita-nightly-bin`.
- Build duration is long because Krita is large and built from source.
- Upstream/KDE network or dependency changes can break individual nightly runs.
