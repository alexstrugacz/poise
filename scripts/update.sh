#!/bin/bash
set -euo pipefail

REPOSITORY=https://github.com/alexstrugacz/poise.git
RELEASE_API=https://api.github.com/repos/alexstrugacz/poise/releases/latest
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/poise-update.XXXXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

curl --fail --silent --show-error --location --retry 2 --max-time 30 \
    --output "$WORK_DIR/release.json" "$RELEASE_API"
TAG="$(plutil -extract tag_name raw -o - "$WORK_DIR/release.json")"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "GitHub returned an unexpected Poise release tag." >&2
    exit 1
fi

echo "Installing Poise ${TAG#v} from source…"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$REPOSITORY" "$WORK_DIR/source"
if [[ "$(git -C "$WORK_DIR/source" rev-parse HEAD)" != "$(git -C "$WORK_DIR/source" rev-parse "refs/tags/$TAG^{commit}")" ]]; then
    echo "The checkout does not match the published release tag." >&2
    exit 1
fi
bash "$WORK_DIR/source/scripts/build.sh" --install
