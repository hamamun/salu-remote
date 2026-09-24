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
| `playback.resume` | **v1.1 (§17.5, added 2026-09-22).** The PC's Resume toast, mirrored: `null` while no toast is up, else `{"position": 754000}` (the resumed-at clock it displays). Presence *is* the offer — it is what makes and unmakes the phone's **Start over** seat, and the phone draws no other conclusion from it. |
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
4. **`clearQueue()`** (v1.1, 2026-09-22) — the absolute Clear, so the playlist panel's bin
   and the remote's `queue_clear` are one call rather than two that can drift (§17.4).
5. **`restart()`** (v1.1, 2026-09-22) — already exists for the Resume toast's own
   word-action; the remote's `restart` verb calls the same method and needs **no**
   `fromRemote` flag. On purpose: this action shows no card of its own (closing the toast
   *is* its feedback), so there is nothing for A1 to suppress.

Nothing else in `TransportActions` changes. There is exactly one implementation of
"what Pause means" in SALU, and the phone uses it.

### 7.5 Web mode and focus (D8)

After every command that can begin playback (`play_pause`, `next`, `previous`,
`jump_to_index`, `open_url`, and v1.1's `restart`), if the result is actually playing
**and** SALU is not showing the player:

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

**Facts that shape the fix:**

- SALU **cannot** learn the answer from the network: if the firewall blocks, the
  phone's hello never reaches the PC — the PC never knows anyone tried. The question
  must therefore be asked **when the feature is switched on**, not when the first
  connection arrives. (Plex and KDE Connect do exactly this; Steam & LocalSend
  instead lean on Windows' own popup, which carries the Cancel trap below.)
- Windows' own popup is dangerous: **Cancel silently writes a permanent *Block*
  rule** and Windows never asks again. "Allowing the app" in the control panel
  afterwards can't fix it — a block beats every allow. The block rule has to be
  found and *deleted*.
- Firewall rules point at the exe **path**. SALU is portable: move the folder or
  drop in a new build and the old rule is dead. Every check must compare the rule's
  path against the *running* exe.
- A Private-scoped rule does nothing while the Wi-Fi profile is **Public** — the
  profile has to be asked about too.

**Amended 2026-09-21 — the proactive handshake (tier 2):**

| Trigger | Behaviour |
|---|---|
| Remote toggled **ON** | Probe the rules; only if something needs fixing, the firewall dialog opens on its own: *"Phones on your Wi-Fi need permission to reach SALU. [Allow]"* → one UAC → rule written → verified → *"Available on Wi-Fi · 192.168.0.12 · 7258"*. |
| Every remote start (app launch with Remote enabled, toggle-on restarts) | Silent re-probe — rule exists **and** its path matches the running exe. A bad answer surfaces the panel's **Fix…** row instead of waiting for the 90-second hint. |
| Pairing panel opened | One fresh probe, so a rule just allowed in Windows' own popup never shows a stale Fix row. |

- **Probe** (no admin): the NetSecurity cmdlets in one JSON document — inbound rules
  whose program is this exe or a same-named exe elsewhere (the moved-build trap), plus
  the connection profiles. A failed probe (firewall service off, third-party suite)
  reports *unknown* and the UI stays on the fallback tier below.
- **Fix** (one UAC): an elevated, idempotent script deletes every inbound rule naming
  `salu.exe` (block traps, dead paths) and re-adds the allow — `program + TCP +
  LocalPort 7258-7267 + Private` (the port window is SALU's own §8.1 fallback walk;
  the QR always carries the real bound port). With consent (a checkbox in the same
  dialog), Public networks are flipped to Private in the same elevated step.
- **Verify:** the elevated step is re-probed before the dialog goes green; a declined
  UAC is *cancelled*, a no-change is *failed*, both with honest copy and the manual
  door.
- **Fallback tier, unchanged:** status `running`, server up ≥ 90 s, zero connections
  ever → the panel hint *"Can't connect? Windows Firewall may be blocking SALU."* +
  **Open firewall settings** (`control firewall.cpl`). This covers what SALU cannot
  fix programmatically — third-party antivirus firewalls, group policy.
- **Implementation:** `lib/core/remote/remote_firewall.dart` (pure evaluation /
  parsing / script building + the thin `RemoteFirewallService`), dialog in
  `lib/ui/widgets/remote_firewall_dialog.dart`, the panel's firewall area in
  `remote_panel.dart`, tests in `test/remote_firewall_test.dart`.
- **Phase 9's installer** should add the same rule at install time; the proactive
  flow is exactly what a portable build needs until then.

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
>
> **⚠ Updated 2026-09-22:** one exception in queue editing — `queue_clear` (empty the
> whole playlist) moved into §17.4 for the phone's queue-card clear button. Per-row
> remove and reorder stay v2.

`jump_to_index {index}` · `queue_get {from,count}` · `seek_chapter {delta}` ·
`open_url {url}` · `channel_search {query}` · `channel_play {id}` ·
`track_set {kind:"audio"|"sub", id}` · `mode_set {mode}` ·
`browser_open {url}` / `browser_back` / `browser_reload` / `browser_tabs`.

### Snapshot plumbing

`RemoteService` listens to these and marks the state dirty:
`PlayerService`'s `transportState`, `isPlaying`, `hasMedia`, `currentTitle`,
`position`, `duration`, `volumeLevel`, `isMuted`, `isBuffering`, `shuffleOn`,
`repeatMode`; `BrowserService.mode`; `WindowStateService.mode` + `isFullscreen`;
`QueueService.items`; `OsdController.current` (v1.1 — the deck's one slot, which is
what the Resume toast appears on, §17.5); plus its own device/controller notifiers.

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
window — with no phone involved. (v1.1's additions to this step: `queue_get` /
`queue_jump` / `queue_clear`, and `restart` + a `resume` block in the snapshot — the
probe's `o` sends it, and a toast appearing on screen must show up in the printed
snapshot within ~120 ms.)

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
| Phone can never connect, PC looks fine | **Windows Firewall**, or the network profile is Public. (Since the 2026-09-21 amendment, the panel says which and offers the one-UAC fix; the pairing panel itself re-probes on open.) |
| Worked, then broke after SALU was updated/moved | The firewall rule still points at the old exe path (§8.3). The pairing panel shows the stale-rule row with a **Fix…** that re-anchors it. |
| Fix says "Windows didn't apply the change" | Group policy or a third-party antivirus firewall owns the machine — the dialog's *Open firewall settings* / the AV's own allow-list is the way in. |
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
5. **How long the phone may offer *Start over* (added 2026-09-22).** Today the phone's
   seat lives exactly as long as the PC's toast — **4 seconds** — because mirroring the
   toast is the whole point (§17.4) and nothing on the two screens can disagree. If real
   use says 4 s is too short to reach the phone (the user is across the room, the phone is
   face-down), the fix is a decision, not a hack, and there are exactly two honest shapes:
   **(a)** lengthen the PC's toast TTL (one constant, PC-only — both screens follow), or
   **(b)** let the offer outlive the toast: the PC keeps `playback.resume` non-null until
   the item is restarted, played past the resumed point, or another item loads — a PC-side
   rule, so the phone still invents nothing. Not built; the phone's seek bar remains the
   always-available way to start over for as long as the item is playing.
6. **The same slot, other toast actions (added 2026-09-22).** The Undo toast is
   interactive too (`Playlist cleared · Undo`), and the remote's `queue_clear` currently
   leaves that Undo on the PC screen only. Mirroring it the way §17.4 mirrors the Resume
   toast would need the undo *token* to travel as an id (never the queue itself) — a real
   design, deliberately out of v1.1.

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
| `lib/core/remote/remote_fs_service.dart` | **New.** Drive list from the Win32 drive table (`GetLogicalDrives` + `GetDriveTypeW` — **never** probed with `Directory.existsSync`; network and UNC letters are filtered out of the table before any file-system call can touch them, so disconnected mapped drives cannot stall the answer), pinned places, directory listing with the media filter (`MediaUtils.isMedia` / `DropHandler.scanFolderForMedia` for whole folders), subtitle filter (`.srt .ass .sub .vtt`), system-folder hiding, sort, paging, path validation. Read-only: **no write API exists in this file at all**, by design. |
| `lib/core/remote/remote_browser_bridge.dart` | **New.** Mirrors the browser's active tab into `BrowserService` and routes remote nav commands back to the live `BrowserScreen` (§17.7). |
| `lib/core/remote/remote_web_media_bridge.dart` | **New.** Drives the active web page's own `<video>`/`<audio>` element by JavaScript injection — play/pause, position, volume, mute, fullscreen (§17.11). Follows the existing `WebTab.executeScript` pattern (`_pauseAllMediaJs`, the exit-fullscreen script) — 2 s timeout, errors swallowed. Updated 2026-09-23 (pc_part.md A1/A2): the wire units (ms + percent) convert at the script edge, `NaN`/`Infinity` sanitize to `0` + `seekable:false`, writes clamp, and the element pick prefers a playing/visible element while ignoring hidden/zero-box/sub-2-second clips. |
| `lib/core/remote/remote_web_focus_bridge.dart` | **New (2026-09-23).** `web_key` + `web_focus_get` (pc_part.md A3 · §17.13.5): the page's own tab order, arrow/Enter/Escape semantics with the caret rule, and the injected focus ring — pure script builders + a thin `executeScript` adapter, unit-tested without a WebView. |
| `lib/core/remote/remote_command_handler.dart` | Extended with the §17.4 verbs, plus (2026-09-23) `web_tabs_get` / `web_tab_activate` / `web_tab_close` / `web_tab_new` / `web_bookmarks_get` / `web_key` / `web_focus_get` (pc_part.md A3–A5). |
| `lib/core/browser_service.dart` | **Extended (2026-09-23).** The tab-strip mirror (`List<WebTabMirror>` + write-side tab handler) and the focus-script seam (pc_part.md A4/A3), on top of the §17.7 scalar mirror. |
| `lib/core/subtitle_service.dart` | **Small addition:** expose the engine's state as public read-only getters/notifiers — whether a key is configured, whether it is signed in, and the quota/auth pauses (today `_quotaPaused` / `_authPaused` are private). The phone must be able to say *"sign in on the PC"* instead of silently failing. |
| `lib/ui/osc/` | *(nothing)* — the remote panel gains one row (§10.3). |

**No changes needed:** `TuneService` already exposes everything (`setBandGain`, `selectStop`,
`resetBands`, `applyMy`, `saveMy`, `eqStop`, `eqCustom`, `mySlot`, `fileKind`, `autoPick`) and
already coalesces EQ writes at `eqWriteGap = 120 ms`; `PlayerService` already exposes
`selectAudioTrack`, `selectSubTrack`, `setSubDelay`, `loadSubtitleFile`; `SubtitleService`
already exposes `search` / `save` / `saveAndLoad`; `OpenMediaService.playUrl` already handles
"URL vs M3U vs web link" plus health marking. **The remote is still an adapter.**

### 17.4 Verbs added in v1.1

**Queue (read + jump + clear)** — the phone's playlist card. The v1 snapshot already
carries `queue:{kind,count,index}`, so the card can auto-scroll from the snapshot alone;
these verbs fetch the row titles, jump, and clear. **Implement `queue_get`/`queue_jump`
with R1, not R4** — the Play tab wants its playlist card on day one. `queue_clear` was
added 2026-09-22 (user request: the playlist card's clear button) — until the PC ships it,
the phone answers its own `unknown_command` with one plain line ("needs a newer SALU on
the PC"), so an old PC degrades visibly but safely.

| Verb | Args | PC call |
|---|---|---|
| `queue_get` | `{from, count}` (count ≤ 100) | `QueueService` rows → `[{index, title, durationMs?, now}]` — titles only, never paths |
| `queue_jump` | `{index}` | jump the queue to that row and play it (the reserved `jump_to_index`, renamed for symmetry) |
| `queue_clear` | — | stop playback and empty `QueueService` — `TransportActions.clearQueue()`, the *same* door the playlist panel's own bin uses (`PlayerService.clearQueue`: stop, empty, back to the initial state) → snapshot with `queue:{kind:"empty",count:0,index:-1}`. Idempotent: an already-empty queue is `ok`, never an error. The PC's own **Undo** card is the feedback (A1), so a mis-tap on the phone is still recoverable for 5 s. |

`queue_clear` deliberately does **not** focus the window or pull SALU out of Web mode —
§7.5's focus rule is about commands that *begin* playback, and clearing never does.

**Start over · the Resume toast, mirrored (added 2026-09-22).** SALU's Resume toast is
the one *interactive* card on the PC deck: when an item lands at a remembered position it
says **“you resumed at 12:34 — Restart?”** and it lives for 4 seconds (or until Esc, a
click-outside, or any transport action). The phone gets the same offer, in the Play tab's
toggle row beside shuffle/repeat — **not** a second offer of its own.

The rule that makes it one thing instead of two:

| PC (the deck's one slot, `OsdController.current`) | Phone (Play tab, `playback.resume`) |
|---|---|
| `OsdResumeCard` is shown — the toast is up | `playback.resume` is `{"position": 754000}` → the **Start over** seat is on screen, reading the same clock |
| the toast is gone — its 4 s TTL, Esc, a click-outside, any transport action, or another card taking the slot | `playback.resume` is `null` → the seat is gone, within one snapshot (≤ 120 ms) |

| Verb | Args | PC call |
|---|---|---|
| `restart` | — | `TransportActions.restart()` — the toast's own Restart word-action, verbatim: jump to `0:00` and play, which also closes the toast, so the phone's seat disappears on the next snapshot like every other change. `nothing_playing` when the engine holds nothing. |

- **The phone never invents an offer, and the PC never pushes one the phone cannot end.**
  There is no "dismiss the toast from the phone" verb on purpose: the PC closes its own
  toast (4 s, Esc, click-outside), and every one of those paths is already visible to the
  phone as `resume: null`. One direction of truth.
- **`restart` is not gated on the offer still being up.** The 120 ms snapshot window means
  a tap can race the toast's close; when it does, the honest answer is to do the obvious
  thing — start the loaded item over — not to fail. A tap on a seat that is still drawn is
  always a user who wants the item restarted.
- **No new snapshot cost:** one int while the toast is up, one `null` token otherwise.
  An older APK ignores the field (unknown fields are ignored, §6) and simply has no seat —
  which is the truth for it, and costs the PC nothing.
- **One gap, left honest:** if the PC is in Web mode while the toast is still up, the
  phone's Web body has no toggle row, so the offer has nowhere to be drawn. The PC keeps
  mirroring the deck; the 4 s TTL closes it either way.
- **The phone's word is "Start over"**, the PC's is "Restart": the same action, and the
  toast's own documentation already calls it the way Stop becomes "start over"
  (`player_service` / `transport_actions`). The phone-facing wording follows the user's
  own words (2026-09-22); the tooltip carries the resumed-at clock the toast shows.

**Files** — all require `remote_file_access` ON (§17.6), else `file_access_off`.

| Verb | Args | PC call |
|---|---|---|
| `fs_places` | — | `RemoteFsService.places()` → drives + `Now playing` folder + Downloads / Videos / Music / Desktop (the `Now playing` path comes from `PlayerService.currentPath`). Each drive carries `medium: fixed\|removable\|optical\|ram`; network drives are never listed, and a quick place (or `Now playing`) whose folder lives on the network is skipped silently |
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
| `web_tabs_get` | — | the tab strip, mirrored: `{tabs:[{index,title,url,active,loading,hasMedia}], active, count}` (§17.13) |
| `web_tab_activate` / `web_tab_close` | `{index}` | the strip's own select / close (§17.13) |
| `web_tab_new` | `{url?}` | a new tab, on the PC's new-tab page when `url` is absent (§17.13) |
| `web_bookmarks_get` | — | `{entries:[{name,url,folder}]}`, read-only (§17.13) |
| `web_key` | `{key:"ArrowUp"\|"ArrowDown"\|"Enter"\|"Escape"}` | focus walking, injected like the web-media scripts (§17.13, `remote_apk_ui.md` §6.0) |
| `web_focus_get` | — | `{focus:{label,tag,index,count,editable}}` without moving it (§17.13) |

The last six are **feature-flagged**: the PC advertises `web_tabs`, `web_bookmarks` and
`web_key` in `hello.features` only when it implements them, and the phone draws only what
has been promised (§17.13). An older PC and a newer phone still talk — with fewer buttons.

**Web media** — the user's rule (2026-09-20): when the PC's browser page is playing media,
the phone offers **only the basics** — play/pause, seek, volume, mute, fullscreen — because
that is all most online players expose. These verbs drive *the page's own player element*
via JavaScript (§17.11); they are not mpv commands.

| Verb | Args | PC call |
|---|---|---|
| `web_media_get` | — | inject a read script → `{found, playing, position, duration, volume, muted, canFull, seekable, unit}` (`found:false` when the page has no reachable media element) |
| `web_media_toggle` | — | inject play/pause on the media element |
| `web_media_seek` | `{to}` or `{delta}` | set `currentTime` — **both in milliseconds**, `{delta}` relative to now |
| `web_media_volume` | `{percent}` | `element.volume = percent/100` — **integer percent 0–100**, the page player's own volume, never the Windows volume |
| `web_media_mute` | `{on}` | `element.muted = on` |
| `web_media_fullscreen` | — | `requestFullscreen()` / `exitFullscreen()` on the element's container |

Every one of these answers `no_web_media` when the page's player cannot be reached
(cross-origin iframe, DRM) — the phone then hides the controls instead of leaving them
dead.

**Units (fixed 2026-09-23 — this was a real bug, not a detail).** `position`, `duration`,
`to` and `delta` are **milliseconds**, the house unit of every other time on the wire
(`playback.position`, `seek_to`, `seek_by`); `volume` and `percent` are **integer percent
0–100**. The bridge converts at its own edge — `currentTime * 1000` on the way out,
`to / 1000` on the way in, `volume * 100` and `percent / 100` — so JavaScript's seconds and
0–1 never reach the socket. Two more rules for the same reason:

- `web_media_get` includes `"unit":"ms"` and `"volumeUnit":"percent"`, and the PC
  advertises **`web_media_unit`** in `hello.features`. A phone that sees the promise stops
  measuring; one that does not falls back to reading the units off the reply itself.
- **Never `NaN`, never `Infinity`.** A live stream reports `duration: Infinity` and an
  unloaded element `NaN`; neither survives `jsonEncode`, so both become `duration: 0` with
  `seekable: false`. The phone greys its seek controls on that pair alone.

Until the PC ships this, the phone answers in whatever dialect the last read arrived in —
a fractional number can only be `currentTime` in seconds, a whole number is milliseconds —
so the two halves stay usable while they disagree. That fallback is a bridge, not the
design: the units above are the contract.

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

**And one field inside `playback`** (added 2026-09-22) — the Resume toast, mirrored:

```json
"playback":{ …, "resume":{"position":754000} }   // or "resume":null when no toast is up
```

It is nested in `playback` because it is about the loaded item, and it stays one int while
the toast lives. `null` and `{"position":…}` are the whole vocabulary: presence is the
offer (§17.4). The PC's `OsdController.current` is the source, and the deck's slot is
observed like any other notifier (§9), so a card replacing the toast — or the toast timing
out on its own — reaches the phone within one snapshot.

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
- **Drives are enumerated, network shares are not** (no UNC paths in v1). The enumeration comes from the Win32 drive table (`GetLogicalDrives` + `GetDriveTypeW`), never from `existsSync`: letters of type `DRIVE_REMOTE` and UNC paths are dropped before any file-system call can touch them, because probing a disconnected mapped drive blocks the PC for tens of seconds per letter (the 2026-09-22 `fs_places` hang). Volume labels are read only for local drives, off the handler isolate, with a short budget and a bare-letter fallback.
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

Full tab management (list, select, close, new) still needs the tab strip itself to move
into `BrowserService`. That was **v2** when v1.1 was written; the phone side is now built
and waiting for it, so it is specified as its own work package in **§17.13** — including
the read-only bookmark mirror and `web_key`. The downloads shelf stays out: it is a
PC-side surface with nothing a couch user would do with it.

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
| `no_web_tabs` | "Tab control needs an updated SALU on the PC." (a `web_tab*` verb reached a build without the strip mirror) |
| `tab_not_found` | "That tab is no longer open." (an index the strip does not have any more — the phone re-reads) |
| `no_web_bookmarks` | "The PC's browser has no bookmarked pages." |
| `busy` | "The PC is busy — try again in a moment." (a 3-second handler timeout) |

### 17.9 Tests and checklist additions

Unit tests: `remote_fs_test.dart` (drive-table enumeration incl. network/UNC filtering and empty-drive skipping, media/subtitle filters, system-folder rules,
paging, path validation, **and an assertion that no write API exists**),
`remote_tune_test.dart` (preset sets per `fileKind`, ±12 dB clamp, 0.5 dB quantization,
gesture begin/end pairing, speed-stop key mapping),
`remote_subs_test.dart` (engine-state mapping, outcome → error
mapping, `subLine` formatting), `remote_queue_test.dart` (paging windows, the ≤ 100 count
cap, titles-never-paths on local rows *and* streams, and `queue_clear` — its idempotency
and the Undo card it raises; `queue_jump` needs a live engine, so it stays on the manual
list), `remote_snapshot_test.dart` (the resume offer: a `OsdResumeCard` → `{position}` and
*every* other deck card → `null` — including the zero-position case, which is an offer and
must not be mistaken for "no toast"; the block survives `RemoteSnapshot.fromValues` and the
default playback map declares it as `null`; and `restart` with nothing loaded →
`nothing_playing`), and a **snapshot size test** asserting the serialized state
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
21. Tap the phone's Queue `✕` → confirm → the PC stops, the queue empties (`queue.count = 0`
    in the next snapshot), and the PC screen shows the same *Playlist cleared · Undo* card
    its own bin shows → **Undo** on the PC brings the whole list back. Tap `✕` again on the
    now-empty queue → nothing happens, no error toast.
22. Play an item with a resume memory on the PC → the Resume toast appears → the phone's
    Play tab shows **Start over** in the toggle row within a beat, carrying the same clock.
    Tap it → the PC plays the item from `0:00` and the toast closes; the phone's seat goes
    with it. Repeat and let the toast time out (4 s) → the seat disappears **without** a
    tap, and playback is untouched. Repeat and press Esc on the PC → same. The seat must
    never outlive the toast on either screen.
23. **(2026-09-23) Web units.** Open a YouTube video on the PC → the phone's Web body shows
    the video's **real** clock (not 1000× it, not `0:00`). Drag the seek bar to the middle
    and let go → the picture is at the middle within a second, and the thumb does **not**
    snap back to where it was first. Drag the volume to 10% → the page's own volume drops
    while the thumb moves, and stays at 10. Long-press the page card → the diagnostics
    sheet's `Units read` says `time ms · volume %` and the raw reply agrees with it.
24. **Web transport.** −10 s twice in a beat → the page is 20 s back, not 10. A live page
    with no reported length → no seek bar, one line saying why, and the two nudges greyed.
25. **Tabs.** With `web_tabs` advertised: the tab count opens the strip, the rows match the
    PC's own tab bar, tapping one switches the PC's page, ✕ closes it and the list shrinks
    in place, and "New tab" with a URL opens that URL in a **new** tab. Without the flag:
    the same door says so in one line and still opens a URL.
26. **Saved pages.** ☆ → "Save this page" puts the current URL into SALU's URL library with
    the page title as its name (visible in Browse → Streams afterwards, and on the PC);
    tapping a saved row opens it in the PC's browser; with `web_bookmarks` advertised the
    browser's own bookmarks are listed above them, read-only.
27. **D-pad.** With `web_key` advertised: ▲▼ walks the page's focus, the PC draws a ring on
    whatever is focused, the phone's card under the pad names it (`Subscribe · BUTTON · 4 of
    120`), OK clicks it, Esc leaves page fullscreen. Without the flag: the pad is ◀ ▶ only,
    with one line saying what is missing — never a dead button.
28. **A page whose player is out of reach** still behaves: one failed write drops the Web
    body to the nav shape with its one honest line, and navigating somewhere else (the URL
    box, a tab switch) gives the next page a fresh trial instead of staying dropped.

### 17.10 Build-order impact

The APK order in `remote_apk_ui.md` §10 is A1 Play (+playlist card) · A2 Browse ·
A3 Subtitles · A4 EQ (+Speed chips, select mode) · A5 Web body + polish.
On this side that means: **R1 and R2 (§13) are unchanged and still come first** — R1 gains
the two tiny queue verbs (`queue_get` / `queue_jump`, §17.4) so the Play tab's playlist
card works on day one, and (2026-09-22) the *start over* pair: the `restart` verb and
`playback.resume`, so the Play tab's toggle row can mirror the PC's Resume toast the day
the phone's Play body exists — then

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

- **Find:** pick the page's *real* player in the *top document* — the largest
  `video`/`audio` element by `videoWidth × videoHeight` (falling back to duration), **with
  a preference for one that is not paused**, and ignoring elements that cannot be the
  programme (zero size, `display:none`, or a duration under two seconds: those are advert
  bumps, previews and looping background clips). Remember nothing — every command re-finds
  it, so navigation never invalidates a handle. Getting this wrong is the difference
  between "the remote works" and "the remote is muting an advert while the film plays".
- **Read** (`web_media_get`): `!el.paused, el.currentTime, el.duration, el.volume,
  el.muted`, plus whether fullscreen is possible (`el.webkitSupportsFullscreen` or a
  non-null `requestFullscreen` on the container) — **converted to the wire units of §17.4
  before it is sent**: `position`/`duration` in milliseconds, `volume` in integer percent,
  `seekable` = a finite duration greater than zero, and `unit:"ms"` so the phone never has
  to measure. `Infinity` and `NaN` (live streams, unloaded elements) are sent as `0` with
  `seekable:false` — they cannot be encoded in JSON at all.
- **Write** (the other `web_media_*` verbs): `play()/pause()`,
  `currentTime = to / 1000` (or `+= delta / 1000`), `volume = percent / 100`, `muted = …`,
  `requestFullscreen()/exitFullscreen()`. A `to` outside `[0, duration]` is **clamped**, not
  rejected — a thumb dragged past the end means "the end".

**Cost control.** `web.hasMedia` in the snapshot is refreshed by a lightweight find-script
every 500 ms **only while** (a) a device is connected, (b) mode is `web`, and (c) the tab
is active — otherwise no polling at all. Full reads happen only when the phone asks
(~1/s while its Web body is on screen, the same throttle as player positions). Every
injection carries the house 2-second timeout and swallows errors, exactly like `park()`.

Two more cost rules from the phone side (2026-09-23). The phone sends **one read at a
time** — a page that takes four seconds to answer must never find four requests stacked
behind it — and its seek bar is **live**, like the player's own: about 4 writes a second
while a thumb drags, a final one on release, all of them `web_media_seek`. That is well
inside the 30 cmd/s ceiling, but a bridge that is still injecting an earlier seek should
**coalesce**: apply the newest `to`, drop the ones in between. Scrubbing a page is exactly
the workload where a queue of stale seeks shows up as stutter.

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

### 17.13 Web tabs, bookmarks and the focus pad (added 2026-09-23)

**Why this exists.** The phone's Web body grew the doors the couch user actually asked
for: the **open-tab list** with a close button on every row, **new tab**, the **saved and
bookmarked pages**, **−10 s / +10 s** on the page's own player, live seek and volume bars,
and a **D-pad that says what it is about to click**. The phone side is built in
`salu-remote` (its `lib/ui/web_body.dart`, `lib/ui/web_sheets.dart`, `lib/ui/dpad.dart`);
everything it needs from the PC is specified here, and `pc_part.md` is the work order that
walks through it file by file.

**Feature flags, not a version bump.** `proto` stays `1` and every verb here is additive.
The PC advertises what it implements in `hello.features` —

| Feature | Means | Phone behaviour without it |
|---|---|---|
| `web_media_unit` | `web_media_get` speaks §17.4's units (ms + percent) and says so with `unit` | The phone reads the units off the reply itself and answers in kind — usable, but a bridge, not the design |
| `web_tabs` | `web_tabs_get` / `web_tab_activate` / `web_tab_close` / `web_tab_new` | The tab door says *"This PC does not report its tabs yet"* and still opens a URL (`open_url`) |
| `web_bookmarks` | `web_bookmarks_get` | The saved-pages sheet shows only SALU's URL library, which already works |
| `web_key` | `web_key` + `web_focus_get`, **and the focus ring is drawn** | The D-pad is ◀ ▶ only (`browser_nav`), with one line saying what is missing |

An older PC and a newer phone therefore still talk, with fewer buttons — never with dead
ones.

#### 17.13.1 The tab strip has to move into `BrowserService`

§17.7 mirrored one *scalar* set (`webTitle`, `webUrl`, `webCanBack`, `webCanForward`,
`webLoading`, `webTabCount`) because the tabs themselves live in `BrowserScreenState`'s
private `_tabs` / `_active`. A phone cannot read a private field, so:

1. The strip moves (or is mirrored) into `BrowserService` as the single source of truth:
   a `List<WebTabMirror>` plus `activeIndex`, each entry carrying `title`, `url`, `active`,
   `loading`, `hasMedia` — the same values the tab bar already paints.
2. `WebTab` keeps owning its `WebviewController`. The service holds a **mirror**, not the
   controllers, and it is refreshed where the screen already calls `setStripTitle(...)`.
3. Writes go back through one handler the screen installs
   (`BrowserService.setTabHandler(...)`), exactly like `setNavHandler(...)` for
   `browser_nav`: activate = the screen's own tab select, close = the screen's own close
   (its confirmation, its "last tab" rule, its session bookkeeping), new = the screen's own
   add-tab, then navigate. **No second code path** — a remote that closes a tab differently
   from the ✕ on the strip is a bug nobody can reproduce.

Closing the **last** tab is the PC's existing decision and stays that way (whatever its own
✕ does — new-tab page, or close the browser window). The phone shows whatever the next
`web_tabs_get` says; if the browser left Web mode on its own, the snapshot's `mode` flips
and the phone follows, as it always does.

#### 17.13.2 The verbs

| Verb | Args | Reply | Errors |
|---|---|---|---|
| `web_tabs_get` | — | `web_tabs_result {tabs:[{index,title,url,active,loading,hasMedia}], active, count}` | `no_web_tabs` |
| `web_tab_activate` | `{index}` | `ack` | `tab_not_found`, `no_web_tabs` |
| `web_tab_close` | `{index}` | `ack` (+ the new `count` if it is cheap) | `tab_not_found`, `no_web_tabs` |
| `web_tab_new` | `{url?}` | `ack {index}` — the new tab is active | `no_web_tabs`, `invalid_arguments` |
| `web_bookmarks_get` | — | `web_bookmarks_result {entries:[{name,url,folder}]}` | `no_web_bookmarks` |
| `web_key` | `{key}` | `ack {focus:{label,tag,index,count,editable}}` | `no_web_media` is **not** the code here — use `invalid_arguments` for an unknown key |
| `web_focus_get` | — | `ack {focus:{…}}` | as above |

`index` is the strip's own index at the moment of the call, and the phone re-reads after
every change, so an index that has gone stale answers `tab_not_found` rather than closing
the wrong page. **Never accept a negative or out-of-range index silently.**

`web_tab_new {url}` is the only "open" that is guaranteed to make a *new* tab; `open_url`
and `browser_open` keep doing exactly what the PC's own Open-URL modal does. The phone uses
`web_tab_new` when `web_tabs` is advertised and `open_url` otherwise, so both paths must
work.

#### 17.13.3 Size discipline

The frame budget is 8 KB (§6.2) and a tab strip is a list of strings — the one place this
protocol can genuinely overflow. So: **cap the list** (send at most 50 tabs, and say the
real total in `count`), **truncate** each `title` to 80 characters and each `url` to 180,
and never send favicons, histories or anything encoded. Bookmarks the same way: at most 200
entries, titles 80 / urls 180, folders one level deep. If a list would still not fit, send
fewer rows — the phone renders what arrives and shows `count` as the truth.

Neither list ever rides the snapshot. The snapshot keeps its single scalar `web.tabs`,
which is what the phone's nav row shows before anything is asked for.

#### 17.13.4 Bookmarks, read-only

`web_bookmarks_get` mirrors whatever the PC's browser already keeps as its own
bookmarks/ favourites — read-only, because a phone that can silently rewrite the PC's
bookmark bar is a phone that can lose it. If the browser has no bookmark store, do **not**
advertise `web_bookmarks`: the phone then shows SALU's URL library alone, which is already
a complete "saved pages" feature (`library_get` / `library_add`, and the Web body's
**Save this page** writes the current URL and title into it).

#### 17.13.5 `web_key` and the focus ring

Same injection path as the web-media bridge (`WebTab.executeScript`, 2 s timeout, errors
swallowed), same find-the-top-document rule:

- **Read the order:** the page's focusable elements in tab order (`a[href]`, `button`,
  `input`, `select`, `textarea`, `[tabindex]:not([tabindex="-1"])`, filtered to visible and
  enabled), with `document.activeElement` as the current seat.
- **`ArrowDown` / `ArrowUp`:** move one seat forward/back, `scrollIntoView({block:'center'})`,
  `focus()`.
- **`Enter`:** `click()` on the focused element — or, when it is a text field, submit its
  form. **Where a text field has the focus the arrows belong to the caret**, so the same
  keys type-navigate instead of hopping elements; say which it was with `editable:true` and
  the phone's line changes to match.
- **`Escape`:** leave element/page fullscreen, close the topmost dialog. A couch remote with
  no Esc is a remote that can get the PC stuck in a full-screen advert.
- **The ring is part of the feature, not a nicety** (`remote_apk_ui.md` §6.0): draw a
  visible outline on whatever has focus while a phone is connected in Web mode. Without it
  the user is steering blind and the pad is worse than useless.
- **Answer with the focus** — `{label, tag, index, count, editable}` — in every `web_key`
  ack: `label` is the element's own text (`innerText`, `value`, `aria-label`, `alt`,
  `title`, in that order, truncated to 60), `tag` its element name, `index`/`count` its
  seat in the order. That is what turns "I pressed down four times" into "I am on
  *Subscribe · BUTTON · 4 of 120*".

**Honest limits, unchanged:** this walks the page's own tab order, so it is exactly as good
as the site's markup. Canvas-drawn single-page apps that manage focus themselves will not
answer, and nothing injected from outside can fix that. The phone says so in one line when
no focus is reported.
