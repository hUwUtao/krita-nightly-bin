#!/usr/bin/env bash
set -euo pipefail

upstream_repo="${UPSTREAM_REPO:-https://invent.kde.org/graphics/krita.git}"
release_prefix="${RELEASE_PREFIX:-krita-nightly-bin}"
api_url="${GITHUB_API_URL:-https://api.github.com}"

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required." >&2
  exit 1
fi

commit="$(git ls-remote "${upstream_repo}" HEAD | awk '{print $1}')"
if [[ -z "${commit}" ]]; then
  echo "Failed to resolve upstream HEAD for ${upstream_repo}." >&2
  exit 1
fi

short_commit="${commit:0:10}"
tag="${release_prefix}-${short_commit}"
release_url="${api_url}/repos/${GITHUB_REPOSITORY}/releases/tags/${tag}"

status="$(
  curl -sS \
    -o /tmp/release-check.json \
    -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${release_url}"
)"

if [[ "${status}" == "200" ]]; then
  should_build="false"
elif [[ "${status}" == "404" ]]; then
  should_build="true"
else
  echo "Unexpected GitHub API status: ${status}" >&2
  cat /tmp/release-check.json >&2 || true
  exit 1
fi

echo "upstream_commit=${commit}"
echo "short_commit=${short_commit}"
echo "release_tag=${tag}"
echo "should_build=${should_build}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "commit=${commit}"
    echo "short_commit=${short_commit}"
    echo "tag=${tag}"
    echo "should_build=${should_build}"
  } >> "${GITHUB_OUTPUT}"
fi
