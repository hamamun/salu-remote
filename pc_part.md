# PC part — fix the `fs_places` drive scan (work order for the Salu repo)

> **Where this applies:** the PC app repository `hamamun/Salu` (Flutter Windows 10/11
> player). The phone app repository `hamamun/salu-remote` is already updated for
> all of this. This file is the complete instruction set for the PC side — three
> work packages: the drive scan (§1–9, with the acceptance checklist at §9),
> the group-by pill bug (§10), and channel grouping on the phone (§11).

## 1. The bug (confirmed from the code, 2026-09-22)

`lib/core/remote/remote_fs_service.dart` answers the phone's `fs_places` request by
probing every drive letter with a blocking file-system call:

```dart
static Iterable<Directory> _drives() sync* {
  for (int i = 0; i < 26; i++) {
    final String drive = '${String.fromCharCode(65 + i)}:${Platform.pathSeparator}';
    final Directory directory = Directory(drive);
    if (directory.existsSync()) yield directory;   // ← the problem
  }
}
```

For every **mapped network drive that is disconnected** (red X in Explorer), that
`existsSync` makes the Windows SMB redirector try to reach the server first — about
**10–30 seconds per dead letter**. The probe runs on the command isolate, so
`RemoteFsService.places()` blocks, the 3-second handler guard in
`remote_service.dart` fires (`busy`), the phone's 8 s request timeout fires first
("The PC did not answer in time."), and the caller sees an endless
timeout → retry → busy loop. The user's PC has many disconnected mapped drives, so
the answer never arrives.

Two more places in the same file have the same trap:

- `places()` checks the **Now playing** parent folder with `Directory(parent).existsSync()`
  (~line 111) — freezes again whenever a file plays from a network drive.
- Downloads / Videos / Music / Desktop are **guessed** as `join(USERPROFILE, name)`
  and checked with `existsSync()` (~lines 118–135) — wrong location for users who
  relocated those folders (Properties → Location), and again slow if one was
  redirected to the network.

## 2. The rule that fixes it (non-negotiable)

Windows can answer two questions **without touching any drive**:

1. **Which letters exist** — `GetLogicalDrives()` (kernel32). Reads an in-memory
   bitmask; instant.
2. **What kind a letter is** — `GetDriveTypeW("C:\\")` (kernel32). Reads the mount
   table; instant even for a dead network mapping. Returns:
   `DRIVE_UNKNOWN=0, DRIVE_NO_ROOT_DIR=1, DRIVE_REMOVABLE=2, DRIVE_FIXED=3,
   DRIVE_REMOTE=4, DRIVE_CDROM=5, DRIVE_RAMDISK=6`.

New logic: get the letters → get each letter's type → **drop `DRIVE_REMOTE` (and any
UNC path) before any I/O happens** → keep the rest. This runs in microseconds and is
immune to the network state. Only then, for the surviving **local** letters, read
volume labels — and do that off the handler isolate with a time budget.

## 3. Changes in `lib/core/remote/remote_fs_service.dart`

No new packages: use `dart:ffi` against `kernel32.dll` / `shell32.dll`. Declare
`ffi: ^2.1.0` in `pubspec.yaml` for the `calloc` helpers (already in the lockfile
transitively via `shared_preferences_windows`; pure Dart, zero native code added).

### 3.1 Replace `_drives()` with a table-driven scanner

```dart
// kernel32 — in-memory queries only; they never touch the drive or the network.
// (Real code: allocate the Utf16 roots inside `using((arena) …)` or free them.)
final int Function() _getLogicalDrives = ...       // GetLogicalDrives
final int Function(Pointer<Utf16>) _getDriveType = ... // GetDriveTypeW

class DriveInfo {
  const DriveInfo({required this.root, required this.medium});
  final String root;    // "C:\"
  final String medium;  // protocol value below
}

// Win32 type  ->  protocol `medium` string (phone already understands these):
const Map<int, String> _mediumByType = <int, String>{
  3: 'fixed',      // DRIVE_FIXED     — internal disks
  2: 'removable',  // DRIVE_REMOVABLE — USB sticks/disks when inserted
  5: 'optical',    // DRIVE_CDROM     — only when a disc is inside (see 3.2)
  6: 'ram',        // DRIVE_RAMDISK
  // 4 DRIVE_REMOTE and 1 DRIVE_NO_ROOT_DIR are dropped, never yielded.
};

List<DriveInfo> _localDrives() {
  final int mask = _getLogicalDrives();
  final List<DriveInfo> out = <DriveInfo>[];
  for (int i = 0; i < 26; i++) {
    if (mask & (1 << i) == 0) continue;
    final String root = '${String.fromCharCode(65 + i)}:\\';
    final int type = _getDriveType(root.toNativeUtf16());
    final String? medium = _mediumByType[type];
    if (medium == null) continue; // network / no-root / unknown → skip silently
    out.add(DriveInfo(root: root, medium: medium));
  }
  return out;
}
```

Keep a pure seam for tests: `_classifyDrives(int mask, int Function(String root)
typeOf) → List<DriveInfo>` so unit tests can feed fake tables (see §6).

### 3.2 Labels, and skipping empty removable/optical drives

For each surviving letter, call `GetVolumeInformationW(root, …)`:

- returns a label → `name = 'Label (X:)'`;
- returns an empty label → Explorer-style fallback: `Local Disk (X:)` (fixed),
  `Removable Disk (X:)` (removable), `Disc Drive (X:)` (optical),
  `RAM Disk (X:)` (ram);
- the call **fails** (no media / not ready — empty card reader, empty DVD tray) →
  **skip the drive entirely** (matches Explorer's default of hiding empty drives).

**Never call `GetVolumeInformationW` on a `DRIVE_REMOTE` letter** — filtering
happens first, always.

### 3.3 Keep the handler non-blocking

`_localDrives()` itself is microseconds; the label reads are the only part that can
stall (a sleeping USB disk). So:

- run the label pass with `Isolate.run(...)` guarded by
  `.timeout(const Duration(seconds: 2), onTimeout: …)`;
- on timeout, answer with the letters and bare-letter names — never block;
- cache the result ~5 s so a burst of `fs_places` calls costs nothing.

`places()` therefore becomes `Future<RemoteFsPlaces> places({String? nowPlayingPath})`.
Update its single call site accordingly (§4).

### 3.4 Quick places: stop guessing user folders

Resolve Downloads / Videos / Music / Desktop via
`SHGetKnownFolderPath` (shell32) instead of `join(USERPROFILE, name)`:

| Place | KNOWNFOLDERID |
|---|---|
| Desktop | `{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}` |
| Downloads | `{374DE290-123F-4565-9164-39C4925E467B}` |
| Music | `{4BD8D571-6D19-48D3-BE97-422220080E43}` |
| Videos | `{18989B1D-99B5-455B-841C-AB7C74E4DDFC}` |

- If the API fails, fall back to today's `join(USERPROFILE, name)` + `existsSync()`.
- **Skip the chip silently when the resolved path is network-backed**: UNC
  (`\\…` / `//…`) or its root letter is `DRIVE_REMOTE` (corporate folder
  redirection, or Desktop moved to a NAS). Same rule as drives — check the table,
  never probe the path.

### 3.5 Now playing: same network guard

Current code checks `Directory(parent).existsSync()`. Before that check:

- `current.contains('://')` → skip (already there);
- `parent` is UNC or its root letter is `DRIVE_REMOTE` → **skip without any I/O**;
- otherwise the local `existsSync` is safe and stays.

### 3.6 Reply shape (additive, backward compatible)

Each drive place gains one field; everything else is unchanged:

```json
{ "name": "Local Disk (C:)", "path": "C:\\", "kind": "drive", "medium": "fixed" }
```

- `medium` ∈ `fixed | removable | optical | ram` (drives only; omit elsewhere).
- Older phone builds ignore unknown fields — safe. The current phone build
  (salu-remote, already updated) uses `medium` for the chip icon and additionally
  hides any place flagged `net:true`, kind `network*`, or a UNC path — the PC
  should simply never send network-backed places, which is the real guarantee.

## 4. Changes in `lib/core/remote/remote_command_handler.dart`

- `_fsPlaces()` (~line 394) awaits the now-async `places()`:

```dart
Future<RemoteCommandResponse> _fsPlaces() async {
  ...
  'places': (await RemoteFsService.instance
          .places(nowPlayingPath: player.currentPath.value)).toJson(),
}
```

- No other handler changes. The 3-second guard in `remote_service.dart`
  (`handler.handle(command).timeout(const Duration(seconds: 3), … busy …)`) stays
  exactly as-is — after this fix the answer is millisecond-fast, so the guard
  simply never fires for `fs_places`. Do **not** touch the `busy` contract or the
  phone's timeouts.

## 5. Linux/macOS builds

`GetLogicalDrives` is Windows-only. Guard with `Platform.isWindows`:
non-Windows keeps today's behaviour (no drive letters; explicit paths still work —
the feature stays honest, per the existing comment). The quick-place resolution may
fall back to `USERPROFILE`/`HOME` + `existsSync` off Windows as today.

## 6. Tests — extend `test/remote_fs_test.dart`

- `_classifyDrives` with a fake table: mask `A..Z` where `C`=`FIXED`, `E`=`REMOVABLE`,
  `F`=`CDROM`, `R`=`RAMDISK`, `W`,`Z`=`DRIVE_REMOTE`, `N`=`DRIVE_NO_ROOT_DIR` →
  result contains exactly C/E/F/R with the right `medium`, and the fake `typeOf` is
  the only function invoked for those letters (assert network letters are dropped
  from the table row, i.e. no label read is ever attempted for them).
- UNC quick place (`\\server\share\Videos`) and now-playing path → place absent.
- Quick place on a `DRIVE_REMOTE` root → absent.
- Label fallback: empty label → `Local Disk (C:)` etc.
- Keep the existing assertions (media/subtitle filters, system-folder rules, paging,
  path validation, no write API).

## 7. Docs to mirror (if present in this repo)

If this repo carries its own copy of `remote.md`, mirror the three amended spots
(already changed in `hamamun/salu-remote`): §17.3 `remote_fs_service.dart` row,
the `fs_places` verb row (new `medium` field), and the §17.6
"Drives are enumerated, network shares are not" rule. `pc_part.md` is authoritative
where copies have drifted.

## 8. Out of scope — do not change

- The 3 s `busy` handler timeout, the phone's timeouts, the auth/pairing flow.
- No write API in `RemoteFsService` (read-only by design — keep it absent).
- No PowerShell / WMI / `wmic` subprocesses — the fix is pure Win32 FFI.
- No UI changes in the PC player's own screens.

## 9. Acceptance checklist (verify on the user's PC shape)

1. PC has **several mapped network drives, all disconnected (red X)** + normal
   local disks → phone's Files tab opens in **under 1 second**.
2. The phone's Drives group matches **This PC** minus network drives: internal
   disks, USB disk/stick when inserted, DVD only with a disc; empty card-reader
   slots and empty DVD drives absent; names like `Local Disk (C:)`, `Data (D:)`.
3. SALU's window **never freezes** while the phone opens Files (old code froze the
   window for the length of the scan — this is the regression test).
4. Play a file from a network drive → Files tab still instant; no Now-playing chip
   pointing into the network.
5. Relocate Videos to `D:\Media\Videos` (Properties → Location) → the Videos chip
   opens the new location.
6. `flutter test test/remote_fs_test.dart` green; `dart analyze` clean for the
   touched files.
7. **Pill:** with a phone paired, connected **and actively driving playback**
   (volume nudges, seeks from the phone's Play tab), the group-by pill in the
   playlist panel opens and stays open until tap-outside / Esc / a choice.
8. **Grouping sync:** set Category on the phone → the PC panel pill shows
   Category; set Language in the PC panel → the phone chips move to Language
   on the next snapshot. A phone connected to an OLD Salu build shows no
   chips and no error.

---

## 10. Group-by pill does not open while a phone is connected (investigate and fix)

**Symptom (user, 2026-09-22):** load an m3u so the playlist panel shows the
channel header; the **group-by button stays visible**, but tapping it does not
open the 4-option pill (Flat / Category / Language / Country) **while a phone
remote is connected**. Disconnect the remote → the pill works again.

**Verified from the code (do not re-guess these):** the pill path reads **no
remote state at all** — `_openPill` / `_closePill` / `_hidePillNow` /
`_groupByButton` in `lib/ui/panels/playlist_panel.dart` never consult
`RemoteService`, and `PanelService`'s one-popup exclusivity does not include
the pill. The pill force-hides only on four intentional events: playlist panel
close (`_onPanelToggle`), emptied queue (`_onItemsChanged`), new channel-load
generation (`_onLoadGeneration`), and its own dismiss/choice. So nothing in
the code *should* suppress it — this one needs a live run, not more reading.

**Prime suspect:** `_focusForPlayback()` in
`lib/core/remote/remote_command_handler.dart` (defined near line 305) — it is
called by most playback verbs: the seek/skip family (~64–95), `queue_jump`,
`_restart` ("start over"), `library_play`, and `open_url` when targeting the
player. Every
phone-driven play/seek/volume-jump re-focuses the SALU window; on Windows a
focus grab can dismiss an open root-overlay surface (the pill lives in
`OverlayPortalController` at `OverlayChildLocation.rootOverlay`). While the
phone sits idle nothing fires — matches "disconnect and it's fine".

**Plan, in order:**

1. **Instrument before touching anything:** temporary `debugPrint` in
   `_togglePill`, `_openPill`, `_closePill`, `_hidePillNow` (with which call
   site fired it) plus a print in `_focusForPlayback`; reproduce with the
   phone connected and tapping Play-tab controls. One run names the culprit.
2. Fix shape once named: the pill must close **only** through its three
   intentional doors (tap outside, Esc, a choice). If `_focusForPlayback` is
   the killer, exempt the pill: re-assert `_pill.show()` after the focus grab,
   or scope the grab so it never runs while a pill is open, or make the
   overlay ignore focus-loss dismissal. Check the OSD-card layer too if the
   log points there (remote volume/seek raises an OSD card over the pill's
   hit area).
3. No protocol or phone changes involved — pure PC UI bug. Keep
   `ChromeLock` semantics (pill holds a lock) intact.

## 11. Channel grouping on the phone (new protocol + PC duties)

The phone must offer the same four modes as the PC's pill
(flat / category / country / language) with icon chips above the queue and
group headers inside the queue list. Constraint that shapes everything:
**the phone receives channel titles only — never URLs or m3u metadata**
(`remote.md` privacy rule), so groups must come from the PC, pre-computed.

All grouping logic already exists in `lib/core/channel_grouping.dart` +
`lib/core/channel_view_service.dart` — reuse both so the PC panel and the
phone can never disagree on order (category: provider first-appearance;
language/country: alphabetical; `Unknown` last — `ChannelGrouping`'s own
rules).

1. **Snapshot addition** (additive, old phones ignore it):
   `queue.grouping: { available: ["category"|"language"|"country"],
   mode: "flat"|"category"|"language"|"country" }` — from
   `ChannelGrouping.availability(items)` and
   `ChannelViewService.instance.groupMode`.
2. **New verb `queue_groups`** — answers `{groups:[{key,name,count,start}]}`
   for the CURRENT mode, in exactly `ChannelGrouping`'s descriptor-head order
   (`start` = absolute queue index of the group's first row; `key` = the
   stable key the accordion uses). Empty list in flat mode.
3. **New verb `queue_group_set {by}`** — a pure view change, mirrors
   `_chooseMode` at service level (`ChannelViewService.groupMode.value = by`;
   choosing a grouped mode also opens the group holding the playing channel,
   §10.5). Never touches the queue. Answers `ok` + the next snapshot carries
   the new `queue.grouping`. Unknown `by` → `invalid_arguments`.
4. **The phone plays a group** by tapping it → existing `queue_jump
   {index: start}`; it browses by inserting header rows at the `start`
   positions inside its paged `queue_get` rows (its whole-queue loader is
   already paced and retry-proof — done in salu-remote with this batch).
   Old PCs answer `unknown_command` → the phone hides the
   chips row entirely, no error shown (that code is already in the silent
   set). New PC → old phone: additive JSON, ignored. Safe both ways.
5. **Tests:** reuse `channel_grouping_test.dart` fixtures — assert
   `queue_groups` order and `Unknown`-last parity with `ChannelGrouping`
   descriptors; `queue_group_set` → snapshot roundtrip; empty-flat case.
6. **Also audit** (one pass, likely no change): every remote door that starts
   an m3u (`fs_open`, `library_play`, `library_add` with play) must queue
   through `ChannelLoadService` so items keep their channel names — the
   panel's channel header and this grouping both depend on names. Today's
   doors already do; keep it that way with one assertion in
   `remote_queue_test.dart` (m3u via `fs_open` → `isChannelList` true).

*Phone side (salu-remote, already staged): the paced whole-queue loader is
implemented; the chips row + group headers land after this protocol exists,
behind the `unknown_command` hide — no version gate needed.*

---

## 12. Phone-local channel favourites + queue search (no PC work needed, future sync optional)

**Status (2026-09-23): implemented in salu-remote alone — this section is a record,
not a work order.** The phone's queue card now mirrors the PC panel's header: a search
bar beside Queue (title filter, count + clear button inside, flattens grouped modes
while typing — the panel's §10.3 rule), a favourites bookmark beside the clear button
(channels only), per-row bookmark toggles, and the grouped accordion (every head paints,
only the open group's channels do — a head tap toggles, it never plays; the playing
channel's group opens on its own). The Play tab greys the ±10 s seeks (via the
snapshot's `seekable`) and repeat/shuffle while an m3u is loaded. All of it reuses the
existing verbs/snapshot — no protocol change.

**One honest gap, by design:** favourites are kept on the phone by title (the phone
holds titles only — the privacy rule), so they do not sync with the PC panel's
`ChannelFavouritesService` (stable `tvg-id → tvg-name → name` keys per playlist host).
If sync is ever wanted, the shape is:

1. `queue_get` rows gain `fav: true|false` (one bool per row — no keys cross the wire).
2. New verb `queue_fav_toggle {index}` → `ChannelFavouritesService.toggleFavourite`
   on that row; the next `queue_get` reflects it. Invalid index → `invalid_arguments`.
3. Old phone → new PC: ignores `fav`. New phone → old PC: `unknown_command` on the
   toggle → the phone keeps its local titles as today. Safe both ways, no version gate.

Until then the phone's titles are the favourites — same header filter, same row toggle,
same never-prune rule as the panel, just unsynced.
