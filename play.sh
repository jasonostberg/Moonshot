#!/bin/sh
# Moonshot Nutcracker launcher.
# Checks GitHub for a newer build, installs it if there is one, then starts the game.
# Add this file to Steam as a non-Steam game.
#
#   MOONSHOT_NO_UPDATE=1 ./play.sh    skip the update check
#   ./play.sh --update-only           update without starting the game
# If the repository is private, put a read-only GitHub token in a file named .token next to this script.

DIR="$(cd "$(dirname "$0")" && pwd)"
RAW="${MOONSHOT_RAW:-https://raw.githubusercontent.com/jasonostberg/moonshot/builds}"
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  *)             ARCH=x86_64 ;;
esac
BIN="$DIR/moonshot-nutcracker.$ARCH"
TOKEN=""
[ -f "$DIR/.token" ] && TOKEN="$(tr -d ' \n\r' < "$DIR/.token")"

fetch() { # url, output file
  if [ -n "$TOKEN" ]; then
    curl -fsSL --connect-timeout 5 -H "Authorization: token $TOKEN" -o "$2" "$1"
  else
    curl -fsSL --connect-timeout 5 -o "$2" "$1"
  fi
}

update() {
  command -v curl >/dev/null 2>&1 || { echo "moonshot: curl not found, skipping update" >&2; return 1; }
  TMP="$DIR/.update"
  rm -rf "$TMP"; mkdir -p "$TMP" || return 1
  fetch "$RAW/VERSION" "$TMP/VERSION" || { echo "moonshot: could not check for updates, using the installed build" >&2; return 1; }
  NEW="$(cat "$TMP/VERSION")"
  OLD="$(cat "$DIR/VERSION" 2>/dev/null)"
  if [ "$NEW" = "$OLD" ] && [ -x "$BIN" ]; then return 0; fi
  echo "moonshot: downloading build $NEW" >&2
  fetch "$RAW/moonshot-nutcracker.$ARCH.gz" "$TMP/bin.gz" || { echo "moonshot: download failed" >&2; return 1; }
  fetch "$RAW/SHA256SUMS" "$TMP/SHA256SUMS" || { echo "moonshot: download failed" >&2; return 1; }
  gunzip -c "$TMP/bin.gz" > "$TMP/bin" || return 1
  WANT="$(grep " moonshot-nutcracker.$ARCH\$" "$TMP/SHA256SUMS" | cut -d' ' -f1)"
  GOT="$(sha256sum "$TMP/bin" | cut -d' ' -f1)"
  if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then echo "moonshot: downloaded build failed its checksum, keeping the installed build" >&2; return 1; fi
  chmod +x "$TMP/bin" && mv -f "$TMP/bin" "$BIN" && cp "$TMP/VERSION" "$DIR/VERSION"
  echo "moonshot: now on build $NEW" >&2
}

[ "$MOONSHOT_NO_UPDATE" = "1" ] || update
rm -rf "$DIR/.update"
[ "$1" = "--update-only" ] && exit 0
if [ ! -x "$BIN" ]; then echo "moonshot: no build installed yet and the download failed" >&2; exit 1; fi
exec "$BIN" "$@"
