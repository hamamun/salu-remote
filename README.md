# SALU Remote

SALU Remote is the Android companion app for SALU. The phone connects to SALU on the
same local Wi-Fi and sends playback commands; SALU remains responsible for playback and
for the media itself.

## Current milestone

The current build contains the first working remote loop:

- pair by the SALU PC address and pairing code;
- reconnect to a remembered PC;
- play/pause, stop, previous/next, seek, volume and mute;
- shuffle, repeat and player/web mode commands;
- live playback state and connection feedback from the PC.

The Android permissions, API level, screen-awake channel and persistence dependency are
already applied in this checkout. The next product step is the QR pairing flow and the
three-tab interface (Play, Browse and Tune), after the first phone-to-PC test succeeds.

## Run from Android Studio

1. Open this repository as a Flutter project.
2. Connect an Android phone with USB debugging enabled.
3. From the repository root run `flutter pub get` once.
4. Select the phone and press **Run**.
5. Follow [`SETUP_STEP_BY_STEP.md`](SETUP_STEP_BY_STEP.md) to pair it with SALU.

`remote.md` is the PC-side protocol/implementation specification. `remote_apk_ui.md` is
the Android interface specification. They are design and implementation references, not
additional setup commands.
