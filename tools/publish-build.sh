#!/bin/sh
# Publishes builds to the "builds" branch, which holds only the latest build (one commit, replaced each time).
# Usage: tools/publish-build.sh <dir containing moonshot-nutcracker.arm64 and .x86_64> <version>
set -e
SRC="$1"; VER="$2"
[ -n "$SRC" ] && [ -n "$VER" ] || { echo "usage: $0 <build dir> <version>"; exit 1; }
REMOTE="$(git config --get remote.origin.url)"
W="$(mktemp -d)"
for a in arm64 x86_64; do gzip -9 -c "$SRC/moonshot-nutcracker.$a" > "$W/moonshot-nutcracker.$a.gz"; done
( cd "$SRC" && sha256sum moonshot-nutcracker.arm64 moonshot-nutcracker.x86_64 ) > "$W/SHA256SUMS"
printf '%s\n' "$VER" > "$W/VERSION"
cd "$W"
git init -q -b builds
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-Claude}" -c user.email="${GIT_AUTHOR_EMAIL:-noreply@anthropic.com}" commit -q -m "Build $VER"
git push -f "$REMOTE" builds
