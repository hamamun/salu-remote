# SALU Remote — PC-Side Implementation Spec (Phase 8, Part 1)

**Status:** 📝 Decisions locked, not implemented — scope extended to **v1.1** on
2026-09-20 (§17: files, streams, EQ + speed, subtitles, mode/web, web media, queue).
**Scope of this file:** the **Windows/PC side only** — the server, the protocol, the
Right-click → QR option, and the Settings toggle.
**Not in this file:** the Android app's screens and behaviour → see `remote_apk_ui.md`
(the APK design is done there; building the APK is a separate later project).
**Companion files:** `remote_opinion.md` (the reasoning), `phase_8_details.md` (the original sketch).

> **How to use this file in a new chat:**
> *"Read `remote.md` and `salu_context.md`. Implement the PC side of SALU Remote,
> in the R1 → R2 order listed in §13. Do not design the Android app — that is a
> separate project. Follow the repo's existing conventions."*

---

## 1. The locked decisions

These were agreed on **2026-09-20**. They are final for v1.

| # | Decision |
|---|---|
| D1 | **PC = server, phone = client.** SALU runs a small WebSocket server. The phone is a native Flutter **APK** — not a PWA, not a WebView, not a browser page. |
| D2 | **QR pairing is the main way in.** The PC shows a QR; the phone scans it once and is remembered forever. Manual IP + code entry always exists as a fallback. |
| D3 | **mDNS is NOT the foundation.** Auto-discovery is a *bonus* (P3, §12) and when built it is a **UDP broadcast beacon**, not mDNS. mDNS fails too often on real home routers. |
| D4 | **Every connection is authenticated.** Pairing code → device token. Non-private (non-LAN) peers are refused. Browsers are refused. |
| D5 | **Position updates are throttled (~4/s); events go instantly.** Every message is a **full state snapshot**, never a diff. |
| D6 | **The phone survives disconnects.** Auto-reconnect on the phone, connection dot, keep-screen-awake. The PC pushes a full snapshot on every new connection. |
| D7 | **Version handshake.** `proto: 1` on every message set. Mismatch = a clear error, never a half-working app. |
| D8 | **Any *playback* command arriving while the PC is in **Web mode** switches SALU back to **Player mode** and focuses the window.** *⚠ Revised 2026-09-20 (v1.1):* "Web-mode verbs are v2" no longer holds — mode switching, web navigation and web-media control are now in scope (§17.4, §17.7, §17.11). What stays: a *transport* command (play/pause/seek/next…) still pulls SALU back to Player mode — in Web mode the phone talks to the page's player, not to mpv. |
| D9 | **QR door = right-click strip, rightmost item** (after Settings). *This supersedes the old code comment in `right_menu.dart` that reserved the slot "between repeat and Info" — that comment must be updated.* |
| D10 | **Settings gets a Remote toggle, default ON.** Off = the listener really closes and the port is freed. |
| D11 | **DROPPED:** playing media *on the phone*, and streaming a live preview of the PC screen to the phone. Not now, not in this phase. |
| D12 | Commands go into **`TransportActions`** (SALU's own transport facade) — never straight into `PlayerService`, never a second implementation of transport. |

### Decisions I made on your behalf — flip any of these, they are cheap to change

| # | Decision | Why |
|---|---|---|
| A1 | Remote commands **do** show OSD cards on the PC screen — **except volume and mute** (you are already looking at your phone for those). | Seeing `>> +15s` on the PC is reassuring; seeing a volume card flash on the TV from across the room is not. |
| A2 | **"Control" is informational, not a lock.** Any paired phone may send a command; doing so makes it the shown controller. No allow/deny popups. | Two paired phones belong to the same person. A permission dance is friction for zero security. |
| A3 | **No absolute file paths** are sent to the phone — title only. | The phone never needs `D:\Movies\…`, and it is one less thing to leak. **⚠ Revised 2026-09-20 (v1.1):** the user asked for a file browser on the phone, so paths now travel **on demand, by explicit taps, to an authenticated device**, behind a separate switch — see §17.6. Paths are still never part of the automatic state snapshot. |
| A4 | The QR panel is a **centered modal dialog**, same recipe as `OpenUrlDialog` / Settings. | The QR must be big enough for a camera, and pairing deserves full attention. No new `PanelService` popup tier needed. |
| A5 | Pairing **code rotates when the panel closes** (and immediately after a successful pairing). The code never changes while the panel is on screen. | A QR photographed over someone's shoulder stops working; a user mid-scan is never sabotaged by a rotation. |
| A6 | The APK project lives **outside** this repo for now; the shared protocol file is copied with a "do not edit separately" header. | Keeps this repo clean while the APK's UI is still being designed. Revisit later (§16). |

---

## 2. Non-goals for this phase

- ❌ Playing/casting media on the phone.
- ❌ Screen mirroring / video preview on the phone.
- ❌ Any internet/cloud relay, accounts, or pairing over the internet.
- ❌ mDNS/Bonjour (replaced by the UDP beacon, P3 only).
- ❌ Playing/casting media on the phone, screen preview, image thumbnails over the socket, and any file delete/rename/move/upload. **Still out, permanently.**
- ✅ **Now IN scope (added 2026-09-20, v1.1 — see §17):** the PC file browser, the saved-URL
  (M3U) library, the equalizer, the subtitle engine (tracks, sync, search, download), the
  Player↔Web mode switch, and basic web navigation control.
- ❌ Any HTTP endpoint. The server speaks **WebSocket only** — there is no web page to attack, and no CORS surface.

---

## 3. Why this is small work in this codebase

The architecture is already right; the remote is an **adapter**, not a subsystem.

| Existing thing | What it gives us |
|---|---|
| `TransportActions.instance` — "the single transport facade" | The remote becomes a **third caller** beside the buttons and the keyboard. |
| `PlayerService`'s `ValueNotifier`s (`transportState`, `isPlaying`, `position`, `duration`, `volumeLevel`, `isMuted`, `isBuffering`, `currentTitle`, `hasMedia`, `shuffleOn`, `repeatMode`, `trackSurface`) | The state broadcaster is just "listen to these, build one JSON object". We never ask mpv anything. |
| `QueueService.items` / `isChannelList` | Free `queue.count` / `queue.index` / `queue.kind` in the snapshot. |
| `BrowserService.instance.mode` (`SaluMode.player|web`), `setMode`, `isWeb` | The Web-mode rule (D8) is one listener + one call. |
| `WindowStateService.instance.mode` (`WindowMode.full|mini`), `isFullscreen` | Snapshot's `window` field. |
| `SettingsService` (`shared_preferences`, notifier per key, load before first frame) | `remoteEnabled` slots in beside `autoEq` / `mouseOverPreview`. |
| `ChromeLock` + the `showGeneralDialog` recipe in `open_url_dialog.dart` / `_openSettings` | The QR panel's shell is copy-paste, not new design. |
| `BrowserService.instance.scheduleStartupWarmUp()` in `main.dart` | The exact pattern for "start the remote after the first frame, never delay a cold start". |
| `right_menu.dart`'s `_door()` + `widthFor()` + `placement()` | The QR item is one more `_button`, one width constant, and the placement maths already adapts. |

**Zero changes are needed in `PlayerService`.** That is the sign the design is right.

---

## 4. Architecture

```
        PHONE (SALU Remote APK)                    PC (SALU)
  ┌──────────────────────────────┐        ┌────────────────────────────────┐
  │ QR scan → host, port, code   │        │ RemoteService (dart:io)        │
  │ device token (saved)         │        │  HttpServer → WebSocket        │
  │ auto-reconnect + backoff     │◀──────▶│   ├ auth (token | pair code)   │
  │ big buttons, slider, queue   │  ws:// │   ├ RemoteCommandHandler       │
  └──────────────────────────────┘        │   │    └▶ TransportActions     │
                                          │   └ RemoteBroadcaster          │
                                          │        ├ listens to notifiers  │
                                          │        └ 1 snapshot, 2 clocks  │
                                          └────────────────────────────────┘
```

- **Transport:** plain WebSocket over the LAN (`ws://`). No TLS in v1 — the traffic is
  on your own Wi-Fi, and a self-signed certificate on an IP address would break more
  phones than it protects.
- **One socket, two directions.** The phone sends verbs; the PC pushes snapshots.
- **Nothing polls.** The PC speaks when something changes; the phone is silent unless
  the user touches it.

---

## 5. File map

### 5.1 New files

| File | Contents |
|---|---|
| `lib/core/remote/remote_protocol.dart` | **Pure Dart — zero Flutter imports** (same rule as `web_address.dart`), so `tool/remote_probe.dart` and the future APK can use it. Message builders/parsers, verb + error-code constants, `protocolVersion = 1`. |
| `lib/core/remote/remote_pairing.dart` | Pairing-code generation (Crockford-style alphabet, no `0/O/1/I/L`), code rotation/expiry bookkeeping, device-token generation (32 random bytes, base64url), token hashing, and the remembered-device store (needs `crypto` as a direct dependency). |
| `lib/core/remote/remote_network.dart` | Pure functions: enumerate IPv4 addresses, keep private ranges only, drop virtual adapters, rank Wi-Fi/Ethernet first. Unit-testable, no I/O in the pure part. |
| `lib/core/remote/remote_service.dart` | The server itself: lifecycle (start/stop/restart), `HttpServer` + `WebSocketTransformer`, the auth gate, socket bookkeeping, the snapshot builder, the two send clocks, the pairing-code timer, the firewall hint timer. Exposes the notifiers the UI reads. |
| `lib/core/remote/remote_command_handler.dart` | Verb → `TransportActions` / `PlayerService` mapping (the table in §9), including the Web-mode/focus rule (D8) and the OSD policy (A1). |
| `lib/ui/osc/remote_panel.dart` | The QR modal (§10.2) — same shell as `open_url_dialog.dart`. |
| `tool/remote_probe.dart` | **R1's test client.** A plain Dart CLI (no Flutter imports) that connects to `127.0.0.1`, prints `hello`, prints every snapshot, and accepts one-letter commands so the whole protocol can be driven from a terminal before any Android work starts. |

**Added in v1.1 (§17)** — `lib/core/remote/remote_fs_service.dart` (PC file browser:
drives, listing, filters, paging) and `lib/core/remote/remote_browser_bridge.dart`
(mirroring the browser's active tab so the phone can see and drive it).

### 5.2 Edited files (exact insertion points)

| File | Change |
|---|---|
| `pubspec.yaml` | Add `qr_flutter` (QR rendering, pure Dart — verify the latest version at implementation time). Promote `crypto` from transitive to a direct dependency (it is already in `pubspec.lock`) for token hashing. |
| `lib/core/settings_service.dart` | `remoteEnabled` (`ValueNotifier<bool>`, default **true**), key `remote_enabled`, `setRemoteEnabled(bool)`, plus the read line in `load()`. |
| `lib/ui/osc/right_menu.dart` | Add `QrMark` as the **last** item after Settings, with a `SizedBox(width: 6)` before it; add an `onRemote` callback beside `onSettings`; update `widthFor`; **replace the stale class comment** about the reserved slot. |
| `lib/ui/widgets/salu_marks.dart` | Add `QrMark` (thin outline, `markStrokeFor(size)`, `markInk(context)` — same recipe as `InfoMark`). |
| `lib/ui/screens/home_screen.dart` | Add `_openRemote()` mirroring `_openSettings()` (closeAll → wakeChrome → ChromeLock → `showGeneralDialog` with the 220 ms fade+scale, barrier `0x99000000`, dismissible), and pass `onRemote: _openRemote` to `RightMenu`. |
| `lib/ui/widgets/settings_dialog.dart` | New **Remote** section in the **General** tab (the app-wide toggles live there; the Web tab stays browser-only). |
| `lib/main.dart` | `await RemoteService.instance.load();` in the pre-first-frame block, and `RemoteService.instance.scheduleStartup();` immediately after `BrowserService.instance.scheduleStartupWarmUp();`. |
| `lib/core/transport_actions.dart` | `fromRemote` flags + one new public seek entry point (§7.4). |

**No edit** to `player_service.dart`, `queue_service.dart`, or `browser_service.dart`.

### 5.3 Exact sizes for the strip (do the arithmetic once, never guess)

`_button` renders a `SaluIconButton(size: 30)`; gaps are `SizedBox(width: 6)`, with a
wider `14` divider before the Info/Settings group; the capsule adds `7` padding + `1`
border per side = **16**.

| Mode | Items | Width |
|---|---|---|
| Channel list (today) | Info · Settings | `30+6+30 + 16 = 82` |
| Full canvas (today) | Shuffle · Repeat · Info · Settings | `30+6+30+14+30+6+30 + 16 = 162` |
| Channel list (with QR) | Info · Settings · **QR** | **118** |
| Full canvas (with QR) | Shuffle · Repeat · Info · Settings · **QR** | **198** |

`RightMenu.placement()` already reads the strip's real size, so nothing else moves.
The existing `test/right_menu_test.dart` must be extended to expect the new widths and
the extra item.

---

## 6. The protocol (v1)

All messages are one JSON object per WebSocket text frame. **Unknown fields are always
ignored** (forward compatibility). Maximum message size: 8 KB.

### 6.1 Handshake

```
server → client   hello        (immediately on connect, before auth)
client → server   auth         (must arrive within 5 s or the socket closes)
server → client   auth_ok      (or: error + close)
```

```json
{"type":"hello","proto":1,"server":"SALU","version":"0.1.0",
 "name":"DESKTOP-ABC","auth":["token","pair"],
 "features":["state","queue"],"state":{ "…full snapshot…" }}
```

```json
{"type":"auth","id":1,"proto":1,"token":"<device token>",
 "device":{"id":"<client id>","name":"Pixel 7","platform":"android"}}
```
```json
{"type":"auth","id":1,"proto":1,"pair":"7K4MQP2X",
 "device":{"id":"<client id>","name":"Pixel 7","platform":"android"}}
```

```json
{"type":"auth_ok","id":1,"deviceId":"a1b2c3","token":"<device token>",
 "control":true,"server":{"name":"DESKTOP-ABC","version":"0.1.0","proto":1}}
```

Notes:
- `auth_ok` **always returns the device token**, including on a re-connect with a
  token the PC already knows. The phone stores whatever it receives — idempotent, no
  branching on the client.
- The `hello` message already carries a full snapshot, so a reconnecting phone paints
  the correct screen in the first frame.

### 6.2 Commands and replies

```json
{"type":"cmd","id":7,"verb":"seek_to","args":{"position":123456}}
{"type":"ack","id":7,"ok":true}
{"type":"error","id":7,"code":"nothing_playing","message":"Nothing is playing on the PC."}
```

- `id` is client-generated and only has to be unique per connection.
- Every `cmd` gets exactly one `ack` **or** one `error`. Never neither.
- `args` is optional; unknown args are ignored.

### 6.3 State

One message type, one shape, always complete:

```json
{"type":"state","rev":42,"at":1758326400123,
 "mode":"player",
 "window":{"mode":"full","fullscreen":false},
 "playback":{"state":"playing","hasMedia":true,"title":"Big Buck Bunny",
             "kind":"video","position":73450,"duration":596000,
             "buffering":false,"seekable":true,
             "volume":80,"muted":false,"shuffle":false,"repeat":"off"},
 "queue":{"kind":"files","count":12,"index":3},
 "control":{"deviceId":"a1b2c3","name":"Pixel 7"},
 "devices":[{"id":"a1b2c3","name":"Pixel 7","online":true,"control":true}]}
```

| Field | Values / notes |
|---|---|
| `rev` | Monotonic counter. The phone ignores any snapshot with `rev` ≤ the last one it applied (protects against reordering). |
| `at` | Server clock, ms epoch — lets the phone measure latency and detect a stalled link. |
| `mode` | `player` \| `web` |
| `window.mode` | `full` \| `mini` — `window.fullscreen` separate |
| `playback.state` | `idle` \| `stopped` \| `paused` \| `playing` (SALU's `TransportState`, verbatim) |
| `playback.title` | Display title only — **never a path** (A3) |
| `playback.kind` | `video` \| `audio` \| `channel` (omit if not cheaply available) |
| `playback.seekable` | `duration > 0 && kind != channel` — the phone greys its seek controls on this alone |
| `queue.kind` | `files` \| `channels` \| `empty` (`QueueService.isChannelList`) |
| `control` | Who is driving, for the phone's "Another phone has control" line (A2) |
| `devices` | Online + remembered devices. Names only, no tokens, no IPs |

**There is no separate `event` message in v1.** A snapshot *is* the event; the phone
diffs it if it wants a toast. Fewer moving parts, one less way to be wrong.

### 6.4 Errors and close codes

| Error `code` | Phone shows | Cause |
|---|---|---|
| `bad_code` | "That pairing code is not valid." | Wrong/expired pairing code. |
| `bad_token` | "This phone is no longer paired." | Token was forgotten on the PC. |
| `version_mismatch` | "Update SALU Remote." | `proto` differs (D7). |
| `nothing_playing` | "Nothing is playing on the PC." | Command needs media; `hasMedia == false`. |
| `not_seekable` | (slider disabled) | Live / unknown duration. |
| `unknown_command` | (silent, logged) | Verb the PC does not know. |
| `too_fast` | (silent) | Rate limit — 30 commands/second. |

| Close code | Meaning |
|---|---|
| `4001` | Unauthorized (no token, bad token, bad code, auth timeout). |
| `4002` | Protocol version mismatch. |
| `4003` | Peer is not a private LAN address. |
| `4004` | Remote control is switched off (toggle flipped mid-session). |
| `4005` | Too many connections (max 4). |

---

## 7. Server behaviour, in detail

### 7.1 Pairing and security

1. **Pairing code** — 8 characters from an unambiguous alphabet
   (`23456789ABCDEFGHJKMNPQRSTVWXYZ` = 40 bits), displayed as `7K4M-QP2X`.
2. **Rotation** (A5): the code is regenerated when the QR panel **closes**, and
   immediately after any **successful pairing**. It never changes while the panel is
   visible.
3. **Device token** — 32 bytes from `Random.secure()`, base64url. The PC stores only
   **SHA-256(token)** in `shared_preferences`; the plaintext is returned once, in
   `auth_ok`, and lives on the phone.
4. **Peer check** — on the WebSocket upgrade, the remote address must be private:
   `10/8`, `172.16/12`, `192.168/16`. Loopback (`127.0.0.1`) is allowed **only** so
   `tool/remote_probe.dart` works. Anything else → close `4003`.
5. **Browser check** — if the upgrade request carries an `Origin` header, refuse it
   (`4001`). Native apps never send one; browsers always do. This kills the entire
   "a website scanned your LAN" class of problem for free.
6. **Auth timeout** — 5 seconds from connect to `auth`, then close `4001`.
7. **Forgotten device** — "Forget" in the panel deletes the token hash; that phone
   gets `bad_token` on its next attempt and must re-pair.
8. **Off is off** (D10) — the toggle closes the listener, stops the timers, drops every
   socket with `4004`, and **frees the port**. Paired tokens survive, so turning it
   back on does not force a re-pair.

### 7.2 Snapshot sending — two clocks, one builder

- **One builder.** `_buildSnapshot()` reads the notifiers and returns the map. Pure
  input → pure output, so it can be unit-tested without an engine (`RemoteSnapshot.fromValues({...})`).
- **Event clock (120 ms debounce).** Any change in transport state, title, media,
  volume, mute, shuffle, repeat, mode, window, queue, devices, or control marks the
  state dirty; a 120 ms coalescing timer sends **one** snapshot for the whole burst.
  Feels instant (under the ~150 ms perception threshold) and stops a volume drag from
  producing 60 messages a second.
- **Position clock (250 ms tick).** While playing, if `position`/`duration` changed
  since the last send, push a snapshot. Never faster than 4/s.
- **Both clocks funnel through the same `_maybeFlush()`**, so a phone can never receive
  a partial picture.
- **New socket = snapshot immediately**, before anything else.

### 7.3 Rate limiting

30 commands/second per device, counted in a 1-second sliding window; over the limit
the command is dropped with `too_fast` and the log gets one line. This exists to
contain a buggy client, not an attacker.

### 7.4 `TransportActions` — the only changes

The facade keeps being the single definition of every transport action (D12).

1. Add an optional `{bool fromRemote = false}` to: `playOrPause`, `stop`, `previous`,
   `next`, `volumeUp`, `volumeDown`, `toggleMute`. When it is `true`, the action runs
   exactly as before but the OSD card is suppressed where A1 says so (volume + mute).
2. Add **one public seek entry point** used by both the PC buttons and the remote:

   ```dart
   // The body that used to live in the private _applySeek().
   void seekBy(Duration delta, {required OsdMark mark, bool fromRemote = false});
   ```
   `seekForward()` / `seekBackward()` become thin wrappers that add the `SeekRamp` step
   and call it. **The ramps stay PC-only** — a phone's `+10 s` button must always be
   +10 s, never 5 → 10 → 15 → 20.
3. Remote `seek_to` (the phone's slider) uses `PlayerService.seekTo()` +
   `TransportActions.instance.resetSeekRamps()` — the same pair the PC timeline
   already uses on a committed seek.

Nothing else in `TransportActions` changes. There is exactly one implementation of
"what Pause means" in SALU, and the phone uses it.

### 7.5 Web mode and focus (D8)

After every command that can begin playback (`play_pause`, `next`, `previous`,
`jump_to_index`, `open_url`), if the result is actually playing **and** SALU is not
showing the player:

```dart
if (BrowserService.instance.isWeb) await BrowserService.instance.setMode(SaluMode.player);
await windowManager.show();
await windowManager.focus();
```

(A minimized window: `windowManager.show()` restores it.) Do **not** focus for volume,
mute, shuffle, repeat, or a pause — stealing focus from another app for a volume tweak
is rude. Mini mode is left alone; the bar is already visible and on top.

---

## 8. Networking details that decide "it just works"

### 8.1 Port

- **Preferred: `7258`** — `S-A-L-U` on a phone keypad. Memorable, easy to write a
  firewall rule for.
- If busy: try `7259 … 7267`, then finally let the OS pick (port `0`).
- **The QR always carries the real bound port.** The phone never assumes a fixed port.
- Persist the preferred port later (P2); v1 keeps it in memory only.

### 8.2 Multiple adapters — the bug that eats an evening

A Windows machine with a VPN, Docker, WSL, Hyper-V, VirtualBox or Tailscale installed
has 5–8 "IPv4 addresses", most of them fake and unreachable from the phone. So:

1. `NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)`
2. Keep only `10/8`, `172.16/12`, `192.168/16`.
3. Drop adapter names matching (case-insensitive): `virtual`, `vethernet`, `hyper-v`,
   `vmware`, `virtualbox`, `loopback`, `bluetooth`, `wsl`, `docker`, `tailscale`,
   `zerotier`, `radmin`.
4. Rank: name contains `wi-fi`/`wifi`/`wireless` → first; `ethernet` → second; rest after.
5. The best one goes into the QR. **All** of them are listed in the panel (P2 dropdown)
   for the rare machine where the guess is wrong.
6. If step 2 or 3 leaves nothing, fall back to the unfiltered private list, and if that
   is empty too, the panel says *"SALU is not on a local network"* and shows no QR.

This is pure logic in `remote_network.dart` with unit tests — exactly the shape of
`web_address.dart`.

### 8.3 Windows Firewall — the #1 support ticket

A background listener is **blocked by default**. The first launch shows Windows'
"Allow SALU to communicate on…?" prompt; if the user hits Cancel (common — it looks
alarming), nothing will ever connect and nothing will look broken.

- **Hint trigger:** status is `running`, the server has been up ≥ 90 s, and **zero
  connections have ever succeeded in this session**.
- **Hint copy (one line in the panel, never a modal):**
  *"Can't connect? Windows Firewall may be blocking SALU."* with a button
  *"Open firewall settings"* → `Process.start('control', ['firewall.cpl'], mode: ProcessStartMode.detached)`.
- **Also say which network we chose:** the panel always shows
  *"Available on Wi-Fi · 192.168.0.12 · 7258"*. One honest line prevents most confusion.
- **The network profile matters:** the Windows network must be **Private**, not Public.
  The hint line above covers this in the same breath.
- **Phase 9's installer** adds the inbound rule for `salu.exe` on the chosen port, so a
  proper install never sees the prompt. Out of scope here — just don't design it out.

### 8.4 Logging

One consistent prefix, matching the repo's existing style:

```
[SALU] remote: listening on 0.0.0.0:7258 (Wi-Fi 192.168.0.12)
[SALU] remote: Pixel 7 paired (a1b2c3)
[SALU] remote: auth failed from 192.168.0.77 (bad_code)
[SALU] remote: rejected 203.0.113.9 (not a private address)
[SALU] remote: stopped (toggle off) — 2 phones remembered
```

---

## 9. Command table (v1)

`Args` in ms for anything time-based. `—` means no args.

| Verb | Args | Does | Failure |
|---|---|---|---|
| `play_pause` | — | `TransportActions.playOrPause(fromRemote: true)` (handles the parked-Stop resume) | `nothing_playing` |
| `stop` | — | `TransportActions.stop(fromRemote: true)` (parks the queue — SALU semantics, not a reset) | `nothing_playing` |
| `next` | — | `TransportActions.next(fromRemote: true)` | `nothing_playing` |
| `previous` | — | `TransportActions.previous(fromRemote: true)` | `nothing_playing` |
| `seek_by` | `{"delta": 10000}` | new `TransportActions.seekBy()` (+10 s / −10 s), clamped to `[0, duration]` | `not_seekable` |
| `seek_to` | `{"position": 123456}` | `PlayerService.seekTo()` + `resetSeekRamps()` | `not_seekable` |
| `set_volume` | `{"value": 0…100}` | `PlayerService.setVolumeUI()` (clamped, never an error) | — |
| `volume_step` | `{"delta": 5}` | `TransportActions.volumeUp/Down(fromRemote: true)` | — |
| `mute_toggle` | — | `TransportActions.toggleMute(fromRemote: true)` | — |
| `shuffle_toggle` | — | `PlayerService.toggleShuffle()` | — |
| `repeat_cycle` | — | `PlayerService.cycleRepeat()` | — |
| `take_control` | — | Marks this device as the controller (A2 — informational only) | — |
| `ping` | `{"at": 1758326400123}` | Replies `{"type":"pong","at":<echo>,"serverAt":<now>}` for latency display | — |
| `state_get` | — | Forces an immediate snapshot (phones use it after resuming from sleep) | — |

### Reserved for v2 (do not implement now, but leave the door open)

> **⚠ Updated 2026-09-20 (second revision):** `queue_get` and `queue_jump` (was
> `jump_to_index`) also moved into v1.1 — the phone's playlist card needs them (§17.4).
> What genuinely remains v2: `seek_chapter`, `track_set` for *style* overrides, full
> browser tab management (new / close / select / downloads shelf), and queue *editing*
> (remove / reorder — the phone can play and add, never rearrange).

`jump_to_index {index}` · `queue_get {from,count}` · `seek_chapter {delta}` ·
`open_url {url}` · `channel_search {query}` · `channel_play {id}` ·
`track_set {kind:"audio"|"sub", id}` · `mode_set {mode}` ·
`browser_open {url}` / `browser_back` / `browser_reload` / `browser_tabs`.

### Snapshot plumbing

`RemoteService` listens to these and marks the state dirty:
`PlayerService`'s `transportState`, `isPlaying`, `hasMedia`, `currentTitle`,
`position`, `duration`, `volumeLevel`, `isMuted`, `isBuffering`, `shuffleOn`,
`repeatMode`; `BrowserService.mode`; `WindowStateService.mode` + `isFullscreen`;
`QueueService.items`; plus its own device/controller notifiers.

---

## 10. PC-side UI

### 10.1 The QR option in the right-click strip (D9)

- **Position:** the very last item, after Settings.
- **Icon:** new `QrMark` in `salu_marks.dart` — three corner finder squares + a sparse
  dot field, drawn with `markStrokeFor(18)` and `markInk(context)`, exactly like
  `InfoMark`. 18 px inside the existing `SaluIconButton(size: 30)`.
- **Label / tooltip:** `Remote`.
- **Behaviour:** `_door(() => widget.onRemote())` — the strip closes first, then the
  panel opens. Same door every other item uses.
- **Widths:** see §5.3 — `widthFor(true) = 118`, `widthFor(false) = 198`.
- **The stale comment** ("Remote has no widget… its future insertion point is between
  repeat and Info") **must be rewritten** to describe the new, deliberate placement —
  otherwise the next person "fixes" it back.
- Mini mode and Web mode never build the strip; the Settings door covers those (§10.3).

### 10.2 The Remote panel (`lib/ui/osc/remote_panel.dart`)

A centered modal, built from the `open_url_dialog.dart` recipe: `showGeneralDialog`,
barrier `0x99000000`, dismissible, 220 ms fade + scale, `ChromeLock` acquired on open
and released on close. Roughly **400 × 520**, radius 16, `AppColors.surface` — the same
shell Settings uses, so it reads as one family.

```
┌─ Remote ───────────────────────────────── ✕ ─┐
│  ● Connected · Wi-Fi · 192.168.0.12 · 7258   │   ← status line (status dot)
│                                              │
│        ┌──────────────────────────┐          │
│        │                          │          │
│        │        [ QR CODE ]       │          │   ← 208 px, on WHITE
│        │                          │          │      with a 12 px quiet zone
│        └──────────────────────────┘          │
│         Scan with SALU Remote                │
│         or enter 7K4M-QP2X                   │
│                                              │
│  Phones                                      │
│   Pixel 7 · has control            ✕ Forget  │
│   Redmi Note · last seen 2 h ago   ✕ Forget  │
│                                              │
│  ⚠ Can't connect? Windows Firewall may be    │
│    blocking SALU.  [Open firewall settings]  │
└──────────────────────────────────────────────┘
```

Rules and copy:

- **Status line** (live): `Starting…` · `● Connected · <network> · <ip> · <port>` ·
  `○ Waiting for your phone` (running, none connected) · `Remote is off — turn it on in
  Settings` · `Couldn't start the remote (port busy)`.
- **The QR sits on a white card.** A dark QR on dark glass scans badly. 12 px quiet
  zone, pure black modules, no rounded corners on the code itself, **no animation and
  no scaling** on the QR widget.
- **QR payload** is a URI, so any camera app can read it and offer to open the app:

  `salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X`

  (`v` protocol · `n` PC name · `h` host · `p` port · `c` pairing code.)
  The APK registers an intent filter for `salu://` later — free deep-link scanning.
- **Manual-entry line** shows the code as `7K4M-QP2X` for phones without a working camera.
- **One honest footnote:** *"This code is only for pairing. It changes when you close
  this panel."*
- **Phones list:** name + `has control` / `connected` / `last seen …`, and a `Forget`
  cross. Empty state: *"No phones paired yet."* Forgetting is immediate (no confirm —
  it is trivially reversible by re-pairing; do **not** add a dialog).
- **Firewall hint** appears only under the §8.3 trigger; it is one line + one button.
- The panel **listens to `RemoteService`'s notifiers**, so a phone pairing while it is
  open appears in the list live. It must not auto-close on pairing.
- **Escape / barrier click / ✕** all dismiss. Dialogs own their Esc above the
  HomeScreen handler, so nothing else needs touching.

### 10.3 Settings → General → Remote section

Slots in after the Equalizer block, using the exact `_AutoEqSwitch` layout (icon tile +
title + helper + `_SaluSwitch`).

```
Remote
Control SALU from your phone over your Wi-Fi.
  ┌────────────────────────────────────────────────┐
  │ [QR tile]  Remote control              ( ●──)  │
  │            Let the SALU Remote app on your     │
  │            phone control playback. Local       │
  │            network only.                       │
  └────────────────────────────────────────────────┘
  ┌────────────────────────────────────────────────┐
  │ Let phones browse PC files          ( ●──)     │   ← v1.1 (§17.6) · default ON
  │ Read-only. Folders and media names only.       │
  └────────────────────────────────────────────────┘
  ┌────────────────────────────────────────────────┐
  │ Show pairing code…                          ›  │   ← opens the same panel
  └────────────────────────────────────────────────┘
  Remembered phones · 2                         ›     ← opens the panel (P2)
```

- **Toggle default: ON** (D10). Off tears the listener down and frees the port; on
  starts it again without a restart and without a re-pair.
- When it is off, `Show pairing code` is disabled with the helper
  *"Turn remote control on to pair a phone."*
- Flipping the toggle while the panel is open updates the panel live.
- The section is **global** — reachable in Player *and* Web mode, and in mini, which is
  what makes it a real off switch rather than a player-only one.

---

## 11. Lifecycle and persistence

| Trigger | Behaviour |
|---|---|
| App start | `SettingsService.load()` (already pre-frame) → `RemoteService.load()` reads the device store → after the first frame, `scheduleStartup()` starts the server **only if** `remoteEnabled` is true. Never delays a cold start. |
| Toggle off | Close sockets (`4004`), stop the HTTP server, cancel the rotation + firewall-hint timers. Notifiers → `off`. Tokens kept. |
| Toggle on | Bind again (same port attempt order), fresh pairing code, status → `running`. |
| No network / no private address | Status → `running` but with *"SALU is not on a local network"* and no QR. Retry binding when the address set changes (a `Timer` re-check every 30 s is enough; do not add a network-plugin dependency). |
| App close | Nothing to do — process exit releases the port. Do **not** add remote work to `_CloseGuard`; it already has enough to flush. |
| Sleep / resume | Dead sockets are reaped by `socket.pingInterval = 20 s`. Phones reconnect and get an immediate snapshot. No PC-side action needed. |

**Storage keys**

| Key | Where | Default |
|---|---|---|
| `remote_enabled` | `SettingsService` | `true` |
| `remote_port` (P2) | `SettingsService` | `7258` |
| `remote_devices` | `RemoteService` (its own JSON list: `id`, `name`, `platform`, `tokenHash`, `addedAt`, `lastSeenAt`) | `[]` |

**`RemoteService` notifiers** (the UI reads these, nothing else):

```dart
enum RemoteStatus { off, starting, running, failed }
ValueNotifier<RemoteStatus>  status
ValueNotifier<String?>       statusDetail   // "Port busy", "Not on a local network"
ValueNotifier<int?>          port
ValueNotifier<String?>       address        // the address the QR carries
ValueNotifier<List<RemoteDevice>> devices   // remembered + online + control flags
ValueNotifier<String?>       pairingCode
ValueNotifier<int>           connectedCount
```

---

## 12. Auto-discovery (P3 — the bonus, build only after R4)

**UDP broadcast, not mDNS.** A beacon is ~30 lines on each side, survives cheap
routers that drop multicast, needs no Bonjour, and cannot half-work.

- **Port `7259`, UDP.** The PC sends a small JSON beacon every 5 s **and** answers any
  probe it receives directly to the sender:
  `{"v":1,"n":"DESKTOP-ABC","h":"192.168.0.12","p":7258,"proto":1,"pairing":true}`
- The beacon is **not** a key: it carries no pairing code and no token. A phone that
  hears it still has to authenticate (§7.1).
- The phone sends one probe on the discovery screen and listens for ~2 s.
- The PC exposes a separate `autoDiscovery` setting, **default off**, so nobody
  broadcasts anything they did not ask for.
- **mDNS is explicitly out of scope.** Bonjour integration buys Apple-ecosystem
  polish at the price of a native plugin, a Windows runtime dependency, and the exact
  failure modes we are avoiding.

---

## 13. Build order and acceptance criteria

### R1 — Server + protocol, proven from a terminal (no Android at all)

1. `remote_protocol.dart`, `remote_pairing.dart`, `remote_network.dart` + unit tests.
2. `remote_service.dart` with auth, snapshot, both clocks, device store.
3. `TransportActions` changes (§7.4); `remote_command_handler.dart`.
4. `tool/remote_probe.dart`.

**Done when:** a terminal session can pair with a code, print a live snapshot every
250 ms, and drive play/pause, seek, volume, mute, shuffle and repeat on a real SALU
window — with no phone involved.

### R2 — The PC UI

`QrMark`, the strip item + widths, the panel, the Settings section, `main.dart` wiring.

**Done when:** the QR renders on white, the toggle starts/stops the server live, and
forgetting a phone blocks it on its next connect.

### R3 — Resilience

Firewall hint, address picking (§8.2), status copy for every state, ping-interval
reaping, rate limiting, the extra unit tests.

**Done when:** a phone can be killed, the PC can sleep, and the next connection is
correct in the first frame.

**R1 and R2 are the whole deliverable.** The APK is a separate project after that.

---

## 14. Test plan

### Unit tests (repo convention: `test/<name>_test.dart`)

| File | Covers |
|---|---|
| `remote_protocol_test.dart` | Build/parse round trips, unknown fields ignored, version mismatch, error codes, `rev` monotonicity helper. |
| `remote_pairing_test.dart` | Code alphabet has no `0/O/1/I/L`; code rotation on panel-close and on pairing; token hash match/mismatch; device store add/forget/last-seen. |
| `remote_network_test.dart` | Private-range filter; virtual-adapter rejection; Wi-Fi > Ethernet ranking; empty result path. |
| `remote_snapshot_test.dart` | `RemoteSnapshot.fromValues({...})` — a pure function over plain values, so no mpv engine is needed (`test/tune_fake_engine.dart` shows the house style for this). |
| `right_menu_test.dart` *(extend)* | Five items on the full canvas, three in channel mode, widths 198/118, the QR mark opens the door. |

### Manual checklist

1. Fresh launch, toggle ON → `[SALU] remote: listening on 0.0.0.0:7258 (…)` in the console.
2. Right-click the canvas → strip → the QR is the rightmost item → the panel opens with
   a scannable code on white.
3. Scan with any phone camera → the URI is readable (`salu://pair?…`) — proves the QR
   is correct before any app exists.
4. `dart run tool/remote_probe.dart --code 7K4M-QP2X 127.0.0.1` → pairs, streams state.
5. Change play state on the PC → the probe's snapshot updates within ~150 ms.
6. Drag volume → snapshots arrive at ≤ 8/second (not one per pixel).
7. Toggle remote OFF in Settings mid-session → the socket drops, the port is free
   (`netstat -ano | findstr 7258` is empty).
8. Toggle ON again → the probe reconnects **without** re-pairing.
9. Put SALU in **Web mode** → send `play_pause` from the probe → SALU is back in Player
   mode and playing, window focused (D8).
10. Forget the device in the panel → the probe's next auth fails `bad_token`.
11. Windows Firewall prompt cancelled on purpose → after 90 s the panel shows the hint
    and the button opens `firewall.cpl`.

---

## 15. Troubleshooting table (put this in the release notes)

| Symptom | Cause |
|---|---|
| Phone connects then instantly drops | Wrong/expired pairing code — the PC refused it correctly. |
| Phone can never connect, PC looks fine | **Windows Firewall**, or the network profile is Public. |
| Works on Ethernet but not Wi-Fi (or the reverse) | Multiple adapters (VPN/WSL/Hyper-V). §8.2; pick the right address in the panel. |
| The right IP, still no connection | Router **AP isolation** / guest network, or the phone is on mobile data. |
| Nothing at all after a router reboot | The PC's IP changed. Pairing is remembered **with** its address — re-scan the QR (the phone should also fall back to discovery/manual entry rather than scrolling a dead IP forever). |
| Time display stutters | Someone removed the throttle (§7.2) or started sending diffs. |
| Remote presses flash OSD cards on the PC | Expected for transport (A1) — volume/mute should stay silent. |
| Stop button on the phone behaves differently from the PC's | The handler was wired to `PlayerService` instead of `TransportActions`. |
| A website can control SALU | Impossible: `Origin` headers are refused and the token never leaves the phone. |

---

## 16. Open questions (deliberately left open)

1. **APK repo location.** A6 keeps it out of this repo for now. Once its UI settles,
   decide: separate repo, or a sibling `remote_app/` folder that shares the protocol
   file. The protocol file is the only thing that must not drift.
2. **Chrome wake on remote commands.** A remote press does not currently wake SALU's
   auto-hiding chrome. Should it (so you can see *what* changed on the PC)? Currently:
   no — the OSD card is the feedback. Revisit after real use.
3. **`window.focus()` on every playback command** — if it ever annoys, gate it behind a
   setting (`Bring SALU to front on remote playback`, default ON).
4. ~~**Web-mode verbs (v2)** — the protocol has room; the decision is when.~~
   **Answered 2026-09-20:** they are in — see §17 (mode_set, browser_nav, the web-media
   bridge). The three questions above are still genuinely open.

Decisions recorded from the APK-scope answers: **§17.12**.

See `remote_apk_ui.md` for the phone app's design opinion.

---

## 17. Expanded scope — v1.1 (added 2026-09-20)

Everything here comes from the user's second round of requirements: the phone must also
browse the PC's files, load the saved M3U/stream list and a typed URL, drive the full
equalizer, drive the full subtitle engine (including OpenSubtitles search and download —
**the download happens on the PC**), and switch/mirror the Player↔Web mode.

The APK's screens for all of this are designed in `remote_apk_ui.md`.

### 17.1 What this supersedes

| Earlier statement | Now |
|---|---|
| §2 "Controlling the PC's browser — v2", "Queue browsing / channel lists — v2" | **In v1.1.** Basic web navigation + the file browser + the URL library are specified below. |
| A3 — "no absolute paths to the phone" | **Revised.** Paths travel on demand, to authenticated devices, behind `remote_file_access` (§17.6). Never inside the state snapshot. |
| §9 "Reserved for v2" | Mostly moved here; the list keeps only what is genuinely still v2. |
| Permanently out | phone-side playback, screen preview, **image thumbnails**, **delete/rename/move/upload**. Do not design these in. |

### 17.2 The rule that keeps the snapshot cheap

**The state snapshot stays small (target < 1 KB) and stays the only push message.**
Everything large or slow is **request → response**, on demand, paged, and cached on the
phone by key:

```
cmd  fs_list   {path, from, count, filter}  →  fs_result   {…}       (paged)
cmd  library_get                            →  library_result{…}
cmd  tune_get                               →  tune_result {…}
cmd  subs_get                               →  subs_result {…}
cmd  subs_search {query}                    →  subs_results{…}
```

Two guards so one slow call can never freeze the remote:

- **Every on-demand handler runs with a 3-second cap** and answers with whatever it has plus
  `"truncated": true` rather than timing out silently.
- **Every directory listing is capped** at 2 000 scanned entries (then sorted, folders first,
  then the requested 200 returned).

### 17.3 New and changed PC files

| File | Change |
|---|---|
| `lib/core/remote/remote_fs_service.dart` | **New.** Drive probe (probe `A:\`…`Z:\` with `Directory.existsSync` — two lines, no PowerShell), pinned places, directory listing with the media filter (`MediaUtils.isMedia` / `DropHandler.scanFolderForMedia` for whole folders), subtitle filter (`.srt .ass .sub .vtt`), system-folder hiding, sort, paging, path validation. Read-only: **no write API exists in this file at all**, by design. |
| `lib/core/remote/remote_browser_bridge.dart` | **New.** Mirrors the browser's active tab into `BrowserService` and routes remote nav commands back to the live `BrowserScreen` (§17.7). |
| `lib/core/remote/remote_web_media_bridge.dart` | **New.** Drives the active web page's own `<video>`/`<audio>` element by JavaScript injection — play/pause, position, volume, mute, fullscreen (§17.11). Follows the existing `WebTab.executeScript` pattern (`_pauseAllMediaJs`, the exit-fullscreen script) — 2 s timeout, errors swallowed. |
| `lib/core/remote/remote_command_handler.dart` | Extended with the §17.4 verbs. |
| `lib/core/subtitle_service.dart` | **Small addition:** expose the engine's state as public read-only getters/notifiers — whether a key is configured, whether it is signed in, and the quota/auth pauses (today `_quotaPaused` / `_authPaused` are private). The phone must be able to say *"sign in on the PC"* instead of silently failing. |
| `lib/ui/osc/` | *(nothing)* — the remote panel gains one row (§10.3). |

**No changes needed:** `TuneService` already exposes everything (`setBandGain`, `selectStop`,
`resetBands`, `applyMy`, `saveMy`, `eqStop`, `eqCustom`, `mySlot`, `fileKind`, `autoPick`) and
already coalesces EQ writes at `eqWriteGap = 120 ms`; `PlayerService` already exposes
`selectAudioTrack`, `selectSubTrack`, `setSubDelay`, `loadSubtitleFile`; `SubtitleService`
already exposes `search` / `save` / `saveAndLoad`; `OpenMediaService.playUrl` already handles
"URL vs M3U vs web link" plus health marking. **The remote is still an adapter.**

### 17.4 Verbs added in v1.1

**Queue (read + jump only)** — the phone's playlist card. The v1 snapshot already carries
`queue:{kind,count,index}`, so the card can auto-scroll from the snapshot alone; these two
verbs fetch the row titles and jump. **Implement with R1, not R4** — the Play tab wants its
playlist card on day one.

| Verb | Args | PC call |
|---|---|---|
| `queue_get` | `{from, count}` (count ≤ 100) | `QueueService` rows → `[{index, title, durationMs?, now}]` — titles only, never paths |
| `queue_jump` | `{index}` | jump the queue to that row and play it (the reserved `jump_to_index`, renamed for symmetry) |

**Files** — all require `remote_file_access` ON (§17.6), else `file_access_off`.

| Verb | Args | PC call |
|---|---|---|
| `fs_places` | — | `RemoteFsService.places()` → drives + `Now playing` folder + Downloads / Videos / Music / Desktop (the `Now playing` path comes from `PlayerService.currentPath`) |
| `fs_list` | `{path, from, count, filter:"media"\|"subs"\|"all", showSystem}` | `RemoteFsService.list(...)` |
| `fs_open` | `{paths:[…], mode:"play"\|"queue"\|"append"}` (≤ 500 paths per call — the multi-select cap) | file → `PlayerService`/`QueueService`; folder → `DropHandler.scanFolderForMedia` then queue; `.m3u`/`.m3u8` → `ChannelLoadService.openSource` |
| `fs_load_sub` | `{path}` | `PlayerService.loadSubtitleFile(path)` (subtitle-picker mode) |

**Streams** — mirror the PC's own library; never a second list on the phone.

| Verb | Args | PC call |
|---|---|---|
| `library_get` | — | `UrlLibraryService.instance.entries` (+ `maxEntries`) |
| `library_play` | `{url}` | `OpenMediaService.playUrl(url)` — one door for streams, M3U URLs and web links |
| `library_add` | `{name?, url, save}` | `UrlLibraryService.add/update` + persist |
| `library_remove` | `{url}` | `UrlLibraryService` removal (allowed: it is the user's own list) |
| `open_url` | `{url}` | `OpenMediaService.playUrl` in Player mode, `BrowserService.openInBrowser` in Web mode — the PC decides, exactly as its own Open-URL modal does |

**Equalizer and speed** — `tune_get` first; the phone never guesses a preset list. The
speed line joins in v1.1 (user approved 2026-09-20): the PC's own stops (`0.5× · 0.75× ·
1× · 1.25× · 1.5× · 2× · 3×`), rendered as chips, with the PC's snapping doing the rest.

| Verb | Args | PC call |
|---|---|---|
| `tune_get` | — | `TuneService`: `fileKind`, `eq`, `eqStop`, `eqCustom`, `mySlot`, `autoPick`, `available`, plus `TunePresets.audio` / `.video` as `{key,label,gains}` |
| `eq_gesture` | `{phase:"begin"\|"end"}` | `beginGesture()` / `endGesture()` — so a drag is one undoable edit on the PC |
| `eq_band` | `{index, db}` | `setBandGain(index, db)` (clamped ±12 dB, quantized to 0.5 dB — the PC's own rule) |
| `eq_set` | `{gains:[10]}` | whole curve in one go (commit) |
| `eq_preset` | `{key}` | `selectStop(TunePart.eq, key)`; `"my"` → `applyMy()` |
| `eq_reset` | — | `resetBands()` |
| `eq_save_my` | — | `saveMy()` |
| `auto_eq` | `{on}` | `SettingsService.setAutoEq(on)` |
| `speed_set` | `{key}` (`"x1"`, `"x1_25"`, …) | `selectStop(TunePart.speed, key)` — the PC's own stop keys, verbatim |

**Subtitles** — the PC does all the work; the phone asks and watches.

| Verb | Args | PC call |
|---|---|---|
| `subs_get` | — | `PlayerService.trackSurface`, `subDelay`, `SettingsService` (auto-download, language) + the new engine-state getters |
| `sub_select` | `{kind:"sub"\|"audio", id}` (`id:"no"` = off) | `selectSubTrack` / `selectAudioTrack` |
| `sub_delay` / `sub_delay_step` / `sub_delay_reset` | `{seconds}` / `{delta}` | `setSubDelay()` (0.1 s step, 1.0 s coarse — the PC's constants) |
| `subs_search` | `{query, language?}` | `SubtitleService.search(query)` → `SubtitleResult` rows verbatim (`fileId, language, title, release, downloads, ext, subLine`) |
| `subs_download` | `{fileId}` | `SubtitleService.saveAndLoad(result)` → outcome mapped to `ack` or the §17.8 errors |
| `subs_auto` / `subs_lang` | `{on}` / `{code}` | `SettingsService` subtitle settings |

**Mode, window, web**

| Verb | Args | PC call |
|---|---|---|
| `mode_set` | `{mode:"player"\|"web"}` | `BrowserService.instance.setMode(...)` |
| `fullscreen_toggle` / `fullscreen_set` | — / `{on}` | `WindowStateService.instance.toggleFullscreen()` / `setFullscreen(on)` |
| `browser_nav` | `{action:"back"\|"forward"\|"reload"\|"stop"}` | routed through the browser bridge (§17.7) |
| `browser_open` | `{url}` | `BrowserService.openInBrowser(url)` (switches to Web mode itself) |

**Web media** — the user's rule (2026-09-20): when the PC's browser page is playing media,
the phone offers **only the basics** — play/pause, seek, volume, mute, fullscreen — because
that is all most online players expose. These verbs drive *the page's own player element*
via JavaScript (§17.11); they are not mpv commands.

| Verb | Args | PC call |
|---|---|---|
| `web_media_get` | — | inject a read script → `{found, playing, position, duration, volume, muted, canFull}` (`found:false` when the page has no reachable media element) |
| `web_media_toggle` | — | inject play/pause on the media element |
| `web_media_seek` | `{to}` or `{delta}` | set `currentTime` |
| `web_media_volume` | `{percent}` | `element.volume = percent/100` — **the page player's own volume**, never the Windows volume |
| `web_media_mute` | `{on}` | `element.muted = on` |
| `web_media_fullscreen` | — | `requestFullscreen()` / `exitFullscreen()` on the element's container |

Every one of these answers `no_web_media` when the page's player cannot be reached
(cross-origin iframe, DRM) — the phone then hides the controls instead of leaving them
dead.

### 17.5 Snapshot additions (small, never big)

Appended to the §6.3 snapshot — every field here is a scalar, a count, or a short string,
so the 250 ms tick stays cheap:

```json
"web":    {"title":"Dune — YouTube","url":"https://…","canBack":true,
           "canForward":false,"loading":false,"tabs":3,"fullscreen":false,
           "hasMedia":false},
"tracks": {"audio":3,"subs":5,"subSelected":true},
"tune":   {"kind":"video","preset":"movie","custom":false,"autoEq":true,
           "speed":"x1"},
"subs":   {"delay":0.2,"lang":"en","autoDownload":true,
           "engine":{"key":true,"signedIn":true,"quotaPaused":false}},
"files":  {"enabled":true},
"library":{"count":7}
```

`web.url` is capped at 256 characters in the snapshot (the full URL is one `browser_get`
away if it is ever needed). Nothing else about the file system appears in the snapshot —
no paths, no entries. `web.hasMedia` is a *boolean only* — the position/duration of a web
page's player never enters the snapshot; the phone asks with `web_media_get` (~1/s, same
throttle as player positions). The v1 queue block (`queue:{kind,count,index}`) is already
everything the playlist card's auto-scroll needs — row titles come from `queue_get`.

### 17.6 Security, privacy and the new switch

The file browser is a real change in what the phone learns, so it gets its own switch and
its own rules:

- **New setting `remote_file_access`** (`ValueNotifier<bool>`, **default ON** — confirmed by
  the user 2026-09-20, General → Remote — §10.3). OFF ⇒ the Files tab in the APK says *"File
  browsing is turned off on the PC"* and every `fs_*` verb answers `file_access_off`. Turning
  the remote off turns this off with it, automatically.
- **Read-only, forever.** There is no write, rename, delete, move, copy or upload path in
  `RemoteFsService` — not disabled, **absent**. A UI that cannot express destruction cannot
  perform it.
- **No file bytes ever cross the socket.** `fs_open` sends *paths*, the PC opens them
  locally. That is what makes a 40 GB file play in one byte of traffic.
- **Media filter on by default**, system folders hidden by default (`Windows`,
  `Program Files*`, `ProgramData`, `$Recycle.Bin`, `System Volume Information`, `AppData`,
  `node_modules`, `WindowsApps`), both overridable per request — never globally.
- **Drives are enumerated, network shares are not** (no UNC paths in v1).
- **The OpenSubtitles API key, username and password never leave the PC.** The phone sends a
  query and gets rows; the PC authenticates. `subs_download` is a request, not a credential.
- Rate limit still 30 cmd/s per device; `fs_list` additionally has a 1-per-200 ms floor so a
  fast thumb cannot hammer the disk.

### 17.7 The one real refactor: mirroring the browser

Today the tabs live in `BrowserScreenState` (`_tabs`, `_active`) — private widget state —
while `BrowserService` only knows `mode`, `stripTitle` and `pageFullscreen`. A phone cannot
read a private field, so v1.1 adds a small bridge:

1. **Read side:** the browser screen already reports its title through `setStripTitle(...)`.
   Next to that call, mirror the active tab into `BrowserService`: `webTitle`, `webUrl`,
   `webCanBack`, `webCanForward`, `webLoading`, `webTabCount` (all `ValueNotifier`s). The
   remote snapshot reads only these.
2. **Write side:** the PC's own back/forward/reload buttons call methods on the active
   `WebTab`. The bridge registers a callback (`BrowserService.setNavHandler(...)`) that the
   screen installs, so `browser_nav` reaches the *same* tab object the buttons use. No
   second navigation path, no duplicated history handling.
3. **`browser_open` needs no bridge** — `BrowserService.openInBrowser` already routes a URL
   into the browser and switches mode.

Full tab management (list, select, close, new, downloads shelf) still needs the tab strip
itself to move into `BrowserService`; that is deliberately **v2** so v1.1 stays small.

### 17.8 Errors added in v1.1

| Code | Phone shows |
|---|---|
| `file_access_off` | "File browsing is turned off on the PC." |
| `path_not_found` | "That folder or file is no longer there." |
| `not_a_directory` | "That path is not a folder." |
| `no_media` | "Nothing is playing on the PC." (the pre-existing `nothing_playing`, kept for transport) |
| `no_key` | "Add an OpenSubtitles key on the PC to search." |
| `signed_out` | "Sign in to OpenSubtitles on the PC to download." |
| `quota` | "OpenSubtitles download limit reached — try again tomorrow." |
| `no_preset` | (silent, logged) an unknown preset key or speed key |
| `no_web_media` | "This site's player can't be controlled from outside." (cross-origin iframe, DRM, or no media on the page) |
| `busy` | "The PC is busy — try again in a moment." (a 3-second handler timeout) |

### 17.9 Tests and checklist additions

Unit tests: `remote_fs_test.dart` (drive probe, media/subtitle filters, system-folder rules,
paging, path validation, **and an assertion that no write API exists**),
`remote_tune_test.dart` (preset sets per `fileKind`, ±12 dB clamp, 0.5 dB quantization,
gesture begin/end pairing, speed-stop key mapping),
`remote_subs_test.dart` (engine-state mapping, outcome → error
mapping, `subLine` formatting), `remote_queue_test.dart` (paging windows, jump clamping,
titles-never-paths), and a **snapshot size test** asserting the serialized state
stays under 1 KB. The web-media JS builder (`remote_web_media_bridge.dart`) gets its own
pure-Dart test: the generated script strings are asserted against fixture pages (one video,
video inside an iframe, no media) — `executeScript` itself cannot run in unit tests.

Manual checklist additions:

12. Files tab → pinned `Now playing` → the current episode is there → tap the next one → it
    plays on the PC without a single byte of file data leaving the machine.
13. `fs_list` on a 20 000-entry folder → answers within ~3 s, 200 rows, `truncated:true`,
    and the socket stays responsive throughout.
14. Turn `remote_file_access` off on the PC → the phone's Files tab changes live to the
    "turned off" copy and every `fs_*` call is refused.
15. Tap a saved M3U URL in the phone's Streams list → the PC loads the channel list exactly
    as if it had been opened from its own Open-URL modal (health dot updates too).
16. Change an EQ band from the phone → the PC's Tune panel slider moves with it, and mpv
    gets one coalesced write, not sixty.
17. Search OpenSubtitles from the phone while signed out → the phone says *"Sign in on the
    PC"* instead of failing silently; after signing in on the PC, the same search downloads
    and the subtitle appears on the PC screen.
18. Put the PC in Web mode → the phone's Play tab becomes the web body within a frame or two,
    and `browser_nav back` moves the PC's page.
19. Open a YouTube video on the PC's browser → the phone's Web body becomes the media shape
    (play/pause, seek, volume, mute, fullscreen); pause from the phone → the PC's page pauses.
20. Open a page whose player sits in a cross-origin iframe (or a DRM site) → the phone hides
    the media controls, shows *"This site's player can't be controlled from outside"*, and
    the nav shape still works.

### 17.10 Build-order impact

The APK order in `remote_apk_ui.md` §10 is A1 Play (+playlist card) · A2 Browse ·
A3 Subtitles · A4 EQ (+Speed chips, select mode) · A5 Web body + polish.
On this side that means: **R1 and R2 (§13) are unchanged and still come first** — R1 gains
the two tiny queue verbs (`queue_get` / `queue_jump`, §17.4) so the Play tab's playlist
card works on day one — then

- **R4 — Files and Streams:** `remote_fs_service.dart`, the `fs_*` / `library_*` /
  `open_url` verbs, the `remote_file_access` switch, `subs_get`'s engine getters.
- **R5 — Tune and Subtitles:** `tune_get` + the EQ verbs + `speed_set`, the `subs_*` verbs,
  the snapshot's `tune` / `subs` / `tracks` blocks.
- **R6 — Mode, web and web media:** the browser bridge (§17.7), the web-media bridge
  (§17.11), `mode_set`, `fullscreen_*`, `browser_nav` / `browser_open`, the `web_*` verbs,
  the snapshot's `web` block.

R4 can ship to the phone before R5 exists (the phone just shows "nothing to adjust"), so the
two can be tested independently on real hardware.

### 17.11 Web media — how it works, and where it honestly fails

The user's rule: **in Web mode, if the page is playing media, the phone gets exactly the
basics — play/pause, seek bar, volume, mute, fullscreen — nothing else.** Most online
players only expose those, so the remote would only be dead buttons if it offered more.

**Mechanism.** SALU's browser already injects JavaScript into pages through
`WebviewController.executeScript` (`WebTab._pauseAllMediaJs`, the find bar's
`WebFind.buildScript`, the exit-fullscreen snippet in `BrowserScreen`). The new
`remote_web_media_bridge.dart` reuses that exact pattern with one new script family:

- **Find:** pick the largest `video`/`audio` element in the *top document* (largest
  `videoWidth × videoHeight`, falling back to duration), remember nothing — every command
  re-finds it, so navigation never invalidates a handle.
- **Read** (`web_media_get`): `!el.paused, el.currentTime, el.duration, el.volume,
  el.muted`, plus whether fullscreen is possible (`el.webkitSupportsFullscreen` or a
  non-null `requestFullscreen` on the container).
- **Write** (the other `web_media_*` verbs): `play()/pause()`, `currentTime = …`,
  `volume = percent/100`, `muted = …`, `requestFullscreen()/exitFullscreen()`.

**Cost control.** `web.hasMedia` in the snapshot is refreshed by a lightweight find-script
every 500 ms **only while** (a) a device is connected, (b) mode is `web`, and (c) the tab
is active — otherwise no polling at all. Full reads happen only when the phone asks
(~1/s while its Web body is on screen, the same throttle as player positions). Every
injection carries the house 2-second timeout and swallows errors, exactly like `park()`.

**Where it honestly fails** — and the phone must hide the controls, not show them broken:

| Case | What happens |
|---|---|
| Player lives in a **cross-origin iframe** (common on streaming sites) | Top-document JS cannot reach it → `found:false` → controls hidden, one line: *"This site's player can't be controlled from outside."* |
| **DRM** players (Netflix-class) | Even same-document elements reject outside control; the read works, writes may not → the phone falls back to the nav shape after one failed write. |
| No media at all | `found:false` → nav shape only. |
| The user navigates | Next `web_media_get` re-finds; between finds, a stale element just no-ops (scripts are wrapped in try/catch). |

**Volume semantics:** `web_media_volume` sets the **page player's own volume** (what the
site's own slider does). It must never touch the Windows system volume — that would be a
surprise the user did not ask for. The nav shape (no media) has no volume control at all.

### 17.12 Decisions recorded from the user's answers (2026-09-20)

| # | Question | Decision |
|---|---|---|
| 1 | File browsing default | **ON** — as proposed (§17.6). |
| 2 | Multi-select | **In scope**, designed in the APK doc §5.1: per-row `▶`/`＋` quick actions, long-press checkbox mode with select-all/deselect, bottom action bar. PC impact: none — `fs_open` already takes a `paths` array (cap 500). |
| 3 | EQ in landscape | Assistant's call: **yes, EQ-only landscape** (mixing-desk layout). No PC impact. |
| 4 | Queue card vs screen | It is the **playlist**: collapsible card, auto-scroll to the current row, **5 rows visible max**, tap a row to jump. PC impact: `queue_get` + `queue_jump` promoted into v1.1 (§17.4, built with R1). |
| 5 | Speed | Assistant's call: **in, as a chips row at the bottom of Tune → Equalizer** (the PC's own stops). PC impact: `speed_set` + `"speed"` in the snapshot's tune block (§17.5). |
| 6 | Activity indicator | Assistant's call: **yes** — one quiet dot in the header, phone-side only, no PC impact. |
| + | Web media | **New rule:** Web mode + page playing media ⇒ only play/pause, seek, volume, mute, fullscreen (§17.11). PC impact: `remote_web_media_bridge.dart` + the `web_media_*` verbs + `hasMedia` in the snapshot. |
