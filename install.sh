#!/bin/sh
# One-time setup on the headset. Installs the launcher and the current build into ~/moonshot.
# Private repository: run with  MOONSHOT_TOKEN=your_token  in front.
DIR="${MOONSHOT_DIR:-$HOME/moonshot}"
MAIN="https://raw.githubusercontent.com/jasonostberg/moonshot/main"
mkdir -p "$DIR" || exit 1
if [ -n "$MOONSHOT_TOKEN" ]; then
  printf '%s\n' "$MOONSHOT_TOKEN" > "$DIR/.token"; chmod 600 "$DIR/.token"
  curl -fsSL -H "Authorization: token $MOONSHOT_TOKEN" -o "$DIR/play.sh" "$MAIN/play.sh" || { echo "Could not download the launcher. Check the token."; exit 1; }
else
  curl -fsSL -o "$DIR/play.sh" "$MAIN/play.sh" || { echo "Could not download the launcher. If the repository is private, a token is needed."; exit 1; }
fi
chmod +x "$DIR/play.sh"
sh "$DIR/play.sh" --update-only || exit 1
echo
echo "Installed in $DIR"
echo "Next: in Steam, add a non-Steam game and browse to $DIR/play.sh"
