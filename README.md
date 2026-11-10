# Moonshot Nutcracker

A multiplayer VR game. Trackers or controllers go on your feet. Kick someone below the belt and they fly into the moon and explode.

Native OpenXR app built with Godot 4.6.1. No browser needed.

## Install on a headset (once)

In a terminal on the headset:

    curl -fsSL https://raw.githubusercontent.com/jasonostberg/moonshot/main/install.sh | sh

Then in Steam, add a non-Steam game and browse to `~/moonshot/play.sh`.

While this repository is private, the headset needs a read-only token:

    curl -fsSL -H "Authorization: token YOUR_TOKEN" https://raw.githubusercontent.com/jasonostberg/moonshot/main/install.sh | MOONSHOT_TOKEN=YOUR_TOKEN sh

## Updates

`play.sh` checks the `builds` branch every time the game starts and installs a newer build if there is one. With no connection it starts the build already installed.

## Diagnostics

Every run writes `~/moonshot/last-run.log` on the headset: system details, a line per second from the game, and, if the game hangs, what each of its threads was waiting on.

To have the log uploaded automatically to this repository's `logs` branch (under `runs/`), save a GitHub token once:

    sh ~/moonshot/play.sh --set-log-token

Use a fine-grained token limited to this repository with Contents set to read and write. The `logs` branch is public while the repository is public.

## Playing

- Strap a controller to each ankle, or wear foot trackers.
- March in place to walk where you are looking.
- A fast foot through the bullseye sends them to the moon.
- Players on the same Wi-Fi share an arena automatically. Alone, you get three practice dummies.
- No headset: it runs in a window. WASD, drag to turn, Space to kick, Esc to quit.

Launch options go after `--`: `--name=YourName`, `--peer=IP.ADDRESS` (internet play, UDP ports 47420-47427).

## Layout

- `source/` the Godot project
- `play.sh` launcher with auto-update
- `install.sh` one-time headset setup
- `tools/publish-build.sh` publishes a build to the `builds` branch
