#!/bin/sh
# Moonshot Nutcracker launcher.
#  1. Checks GitHub for a newer build (and a newer copy of this launcher) and installs it.
#  2. Starts the game with its output going to last-run.log.
#  3. If a log token is set, uploads that log to the repository's "logs" branch every few
#     seconds, so a freeze can be diagnosed without anyone reading text off the headset.
#
#   ./play.sh --set-log-token    save a GitHub token for log upload (asks for it, then tests it)
#   ./play.sh --update-only      update without starting the game
#   MOONSHOT_NO_UPDATE=1         skip the update check

LAUNCHER_VERSION=4
# Steam preloads its overlay into every program started from here; keep that for the game
# only, so the small helper commands below stay quiet.
GAME_PRELOAD="$LD_PRELOAD"
unset LD_PRELOAD
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="jasonostberg/moonshot"
RAW="${MOONSHOT_RAW:-https://raw.githubusercontent.com/$REPO/builds}"
API="${MOONSHOT_API:-https://api.github.com/repos/$REPO}"
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  *)             ARCH=x86_64 ;;
esac
BIN="$DIR/moonshot-nutcracker.$ARCH"
LOG="$DIR/last-run.log"
TOKEN=""
[ -f "$DIR/.token" ] && TOKEN="$(tr -d ' \n\r' < "$DIR/.token")"
LOGTOKEN=""
[ -f "$DIR/.logtoken" ] && LOGTOKEN="$(tr -d ' \n\r' < "$DIR/.logtoken")"

fetch() { # url, output file
  if [ -n "$TOKEN" ]; then
    curl -fsSL --connect-timeout 5 -H "Authorization: token $TOKEN" -o "$2" "$1"
  else
    curl -fsSL --connect-timeout 5 -o "$2" "$1"
  fi
}

# ---------------------------------------------------------------- log upload
RUN_ID=""; SHA=""; LASTSUM=""
upload() { # uploads $LOG as runs/$RUN_ID.log on the logs branch, replacing the earlier copy from this run
  [ -n "$LOGTOKEN" ] && [ -n "$RUN_ID" ] && [ -f "$LOG" ] || return 0
  SUM="$(cksum < "$LOG")"
  [ "$SUM" = "$LASTSUM" ] && return 0
  B64="$DIR/.logb64"; BODY="$DIR/.logbody"
  tail -c 300000 "$LOG" | base64 | tr -d '\n' > "$B64" || return 1
  {
    printf '{"message":"run %s","branch":"logs","content":"' "$RUN_ID"
    cat "$B64"
    printf '"'
    [ -n "$SHA" ] && printf ',"sha":"%s"' "$SHA"
    printf '}'
  } > "$BODY"
  RESP="$(curl -sS -m 25 -X PUT -H "Authorization: Bearer $LOGTOKEN" -H "Accept: application/vnd.github+json" \
          --data-binary @"$BODY" "$API/contents/runs/$RUN_ID.log" 2>&1)"
  NEWSHA="$(printf '%s' "$RESP" | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -1 | grep -o '[0-9a-f]\{40\}')"
  rm -f "$B64" "$BODY"
  if [ -n "$NEWSHA" ]; then
    SHA="$NEWSHA"; LASTSUM="$SUM"; echo "ok $(date -u +%H:%M:%S)" > "$DIR/upload-status.txt"; return 0
  fi
  printf 'failed %s: %s\n' "$(date -u +%H:%M:%S)" "$(printf '%s' "$RESP" | head -c 300)" > "$DIR/upload-status.txt"
  return 1
}

if [ "$1" = "--set-log-token" ]; then
  printf 'Paste the GitHub token and press Enter: '
  read -r T
  T="$(printf '%s' "$T" | tr -d ' \n\r')"
  [ -n "$T" ] || { echo "Nothing entered."; exit 1; }
  printf '%s\n' "$T" > "$DIR/.logtoken"; chmod 600 "$DIR/.logtoken"
  LOGTOKEN="$T"; RUN_ID="setup-test-$(date -u +%Y%m%d-%H%M%S)"
  LOG="$DIR/.setup-test.log"; echo "log upload test from $(uname -n | cut -c1-3)... at $(date -u)" > "$LOG"
  if upload; then echo "Log upload works. You are done."; else echo "Upload failed:"; cat "$DIR/upload-status.txt"; fi
  rm -f "$LOG"
  exit 0
fi

# ---------------------------------------------------------------- update
update() {
  command -v curl >/dev/null 2>&1 || { echo "moonshot: curl not found, skipping update" >&2; return 1; }
  TMP="$DIR/.update"
  rm -rf "$TMP"; mkdir -p "$TMP" || return 1
  fetch "$RAW/VERSION" "$TMP/VERSION" || { echo "moonshot: could not check for updates, using the installed build" >&2; return 1; }
  # test switches the developer can change remotely; empty in normal use
  fetch "$RAW/ARGS" "$TMP/ARGS" 2>/dev/null && cp "$TMP/ARGS" "$DIR/ARGS"
  # newer launcher? replace this file and start again, once
  if [ -z "$MOONSHOT_RELAUNCHED" ] && fetch "$RAW/play.sh" "$TMP/play.sh" 2>/dev/null && [ -s "$TMP/play.sh" ] \
     && ! cmp -s "$TMP/play.sh" "$DIR/play.sh" && sh -n "$TMP/play.sh" 2>/dev/null; then
    cp "$TMP/play.sh" "$DIR/play.sh.new" && chmod +x "$DIR/play.sh.new" && mv -f "$DIR/play.sh.new" "$DIR/play.sh"
    echo "moonshot: launcher updated" >&2
    rm -rf "$TMP"
    MOONSHOT_RELAUNCHED=1 exec sh "$DIR/play.sh" "$@"
  fi
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

UPDATE_NOTE="skipped"
if [ "$MOONSHOT_NO_UPDATE" != "1" ]; then
  if update "$@"; then UPDATE_NOTE="ok"; else UPDATE_NOTE="failed"; fi
fi
rm -rf "$DIR/.update"
[ "$1" = "--update-only" ] && exit 0
if [ ! -x "$BIN" ]; then echo "moonshot: no build installed yet and the download failed" >&2; exit 1; fi

# ---------------------------------------------------------------- run with diagnostics
RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
ARGS="$(cat "$DIR/ARGS" 2>/dev/null | head -1)"
{
  echo "== launcher v$LAUNCHER_VERSION  run $RUN_ID =="
  echo "installed build: $(cat "$DIR/VERSION" 2>/dev/null)   update check: $UPDATE_NOTE   arch: $ARCH"
  echo "kernel: $(uname -srm)"
  echo "os: $(grep -E '^(PRETTY_NAME|VERSION_ID|BUILD_ID|VARIANT_ID)=' /etc/os-release 2>/dev/null | tr '\n' ' ')"
  echo "session: XDG_SESSION_TYPE=$XDG_SESSION_TYPE WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP"
  echo "steam: SteamAppId=$SteamAppId SteamGameId=$SteamGameId SteamDeck=$SteamDeck compat_tool=$STEAM_COMPAT_TOOL_PATHS"
  echo "openxr: XR_RUNTIME_JSON=$XR_RUNTIME_JSON  active_runtime=$(readlink -f "$HOME/.config/openxr/1/active_runtime.json" 2>/dev/null)"
  echo "gamescope vars: $(env | grep -i -E '^(GAMESCOPE|SDL_VIDEO|VK_|ENABLE_|MANGOHUD|LD_PRELOAD)' | tr '\n' ' ')"
  echo "extra args from ARGS file: [$ARGS]   args from Steam: [$*]"
  echo "== game output =="
} > "$LOG" 2>&1

# game switches go after a "--"; add one unless Steam's launch options already did
SEP="--"
for a in "$@"; do [ "$a" = "--" ] && SEP=""; done
[ -n "$ARGS" ] || SEP=""
# shellcheck disable=SC2086
LD_PRELOAD="$GAME_PRELOAD" "$BIN" "$@" $SEP $ARGS >> "$LOG" 2>&1 &
PID=$!

dump_threads() { # what every thread of the game is doing; shows what a hung main thread is waiting on
  {
    echo "== thread dump ($1) at $(date -u +%H:%M:%S) =="
    for t in /proc/$PID/task/*; do
      [ -d "$t" ] || continue
      printf '  %s %-16s %s wchan=%s\n' "${t##*/}" "$(cat "$t/comm" 2>/dev/null)" \
        "$(grep '^State:' "$t/status" 2>/dev/null | tr -s '\t ' ' ')" "$(cat "$t/wchan" 2>/dev/null)"
    done
    if command -v gdb >/dev/null 2>&1; then
      echo "== gdb backtrace =="
      timeout 20 gdb -p "$PID" -batch -ex "thread apply all bt 14" 2>&1 | grep -v -E '^\[New LWP|^warning|^Reading|^Loaded' | head -150
    elif command -v eu-stack >/dev/null 2>&1; then
      echo "== eu-stack =="
      timeout 20 eu-stack -p "$PID" 2>&1 | head -150
    fi
    echo "== end thread dump =="
  } >> "$LOG" 2>&1
}

finish() {
  echo "== launcher stopping: $1 at $(date -u +%H:%M:%S) ==" >> "$LOG"
  upload
  kill "$PID" 2>/dev/null
  exit 0
}
trap 'finish "terminated by Steam or the system"' TERM INT HUP

DUMPS=0; QUIET=0; LASTSIZE=0
while kill -0 "$PID" 2>/dev/null; do
  sleep 4 & wait $!
  SIZE="$(wc -c < "$LOG" 2>/dev/null)"
  if [ "$SIZE" = "$LASTSIZE" ]; then QUIET=$((QUIET + 1)); else QUIET=0; fi
  LASTSIZE="$SIZE"
  STALLS="$(grep -c '^STALL' "$LOG" 2>/dev/null)"
  if [ "$DUMPS" -lt 2 ] && [ "${STALLS:-0}" -gt "$DUMPS" ]; then
    DUMPS=$((DUMPS + 1)); dump_threads "game reported a stall"
  elif [ "$DUMPS" -lt 2 ] && [ "$QUIET" -ge 3 ]; then
    DUMPS=$((DUMPS + 1)); QUIET=0; dump_threads "no output for 12 s"
  fi
  upload
done
wait "$PID"; CODE=$?
echo "== game exited with code $CODE at $(date -u +%H:%M:%S) ==" >> "$LOG"
upload
exit "$CODE"
