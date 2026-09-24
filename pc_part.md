# PC part — work orders for the Salu repo

> **Where this applies:** the PC app repository `hamamun/Salu` (Flutter Windows 10/11
> player). The phone repository `hamamun/salu-remote` is already updated for everything
> written here — the code is written and the tests are written, and every door degrades
> politely wherever the PC has not caught up yet. One caveat, stated plainly in A10: the
> sandbox the phone side was written in has **no Flutter SDK**, so `flutter analyze` and
> `flutter test` have not been run on it yet. Do that first.

Two work orders live in this file:

| Part | Date | What | Status |
|---|---|---|---|
| **A** | 2026-09-23 | **The web section** — page-player units (the reported bug), the right media element, `web_key` + the focus ring, the tab strip mirror (list · switch · close · new), the bookmark mirror | **implemented 2026-09-24 — see the record at the end of Part A** |
| **B** | 2026-09-22 | The `fs_places` drive scan (§1–9), the group-by pill bug (§10), channel grouping (§11), phone-local channel favourites (§12, a record, no PC work) | implemented (verified from the code), kept below |

The protocol for Part A is already written into the phone repo's `remote.md` — **§17.4**
(verbs and units), **§17.11** (the web-media bridge) and **§17.13** (tabs, bookmarks,
focus, feature flags). The phone-side UI spec is `remote_apk_ui.md` §4.2, §6.0 and §8.
Read §17.13 once before starting: it is the contract, and this part is the shopping list.

---

# Part A — the web section (2026-09-23)

## A0. What the user reported, and what it means

Five complaints about the phone's Web section, in the user's words:

1. *"seek bar response is abnormal. same is volume bar. mute and play/pause is working."*
2. *"there is no seek forward/backward button."*
3. *"there is no tab closing button and no tab open options."*
4. *"there is no open tab list."*
5. *"there is no bookmarked pages visibility."*

**2–5 are phone-side and are now built** (±10 s buttons, the tab door, Saved pages, the
diagnostics sheet). They need packages **A3**, **A4** and **A5** below to come alive; until
then each door says what is missing and still does the part every PC can already do.

**1 is the interesting one.** The two controls that misbehave — seek and volume — are
exactly the two that carry *a number with a unit*. The two that work — play/pause and mute —
carry no number at all. That is the fingerprint of a units disagreement between the bridge
and the phone, and `remote.md` §17.4 never stated the unit for `web_media_seek` or for the
times in `web_media_get`: §17.11 describes the *JavaScript* (`el.currentTime`, `el.volume`),
which is seconds and 0–1, while every other time on this wire is milliseconds and every
other volume is an integer percent.

The user was asked to run three checks and answered **no to all three**:

| Check | Predicted symptom if the units were the only fault | Answer |
|---|---|---|
| Do the two clocks under the seek bar show the video's real time? | yes → read side fine | **no** — so the *read* of position/duration is wrong |
| Seek to the middle → does the video jump to the very end? | yes → ms read as s | **no** — so an out-of-range seek is not simply clamping to the end |
| Volume to 10% → does the sound stay loud, or the bar spring back to 100? | yes → percent read as fraction | **no** — so volume's two units are probably *not* the fault |

Read together: **something about the times the bridge reports is wrong, and it is not the
clean 1000× story.** Candidates, in the order to check them:

- the read script returns `el.currentTime` / `el.duration` in seconds while the phone was
  told milliseconds (or the reverse) — a clock 1000× off, or a clock stuck near `0:00`;
- `duration` is `NaN`/`Infinity` (an unloaded element, a live stream, a MSE player) and the
  bridge sends it anyway — `jsonEncode` cannot represent either, so the field arrives as
  `null`, or the whole reply fails and the phone keeps a stale reading;
- the reply keys are not the ones §17.4 names (`position` / `duration` / `volume`) — the
  phone reads a missing field as 0, and `0:00 / 0:00` is exactly "not the real time";
- the element being found is not the programme (an advert bump, a preview loop, a hidden
  `<video>` the site keeps warm) — every control then drives the wrong player, which feels
  like a broken seek bar and a volume that "does not do what I dragged";
- the write is guarded rather than clamped (`if (to > duration) return;`), so a big seek
  silently does nothing — which is why "jumps to the end" was *not* the symptom.

**Do not guess between these. The phone can now show you the answer:** in Web mode,
long-press the page card (the one with the title and URL) and the **Web diagnostics** sheet
opens. It lists the PC's `web_media_get` reply **key by key, value by value, exactly as it
arrived**, next to what the phone made of it and which units it deduced. Open it on a
YouTube video paused at a known time and the fault names itself. That sheet exists for this
package; use it first and paste what it says into the fix.

## A1. Make the units explicit — `remote_web_media_bridge.dart`

The contract (`remote.md` §17.4, **fixed 2026-09-23**):

| Field / arg | Unit | Notes |
|---|---|---|
| `web_media_get → position`, `duration` | **milliseconds**, integer | `(el.currentTime * 1000).round()` |
| `web_media_get → volume` | **integer percent 0–100** | `(el.volume * 100).round()` |
| `web_media_get → unit` | `"ms"` | new — the phone stops measuring when it sees it |
| `web_media_get → volumeUnit` | `"percent"` | new |
| `web_media_get → seekable` | bool | new — `duration.isFinite && duration > 0` |
| `web_media_seek → to`, `delta` | **milliseconds** | `to` is absolute, `delta` relative to now; `delta` must work even though the phone currently sends `to` |
| `web_media_volume → percent` | **integer percent** | `el.volume = percent / 100` (this one §17.11 already stated) |

Rules that go with them:

1. **Never send `NaN` or `Infinity`.** A live stream reports `duration: Infinity`, an
   unloaded element `NaN`; `jsonEncode` throws on both, so the whole `web_media_get` reply
   dies and the phone keeps showing a stale reading forever. Sanitize at the bridge edge:
   not finite → `0` plus `seekable:false`. The phone greys its seek bar and its ±10 s
   buttons on that pair alone and says *Live / not seekable* in one line.
2. **Clamp a write, never reject it.** `to` outside `[0, duration]` means "the end" or "the
   start" — a thumb dragged past the end is not an error. (`invalid_arguments` is for a
   malformed arg, not for an ambitious one.)
3. **Coalesce seeks.** The phone's seek bar is now *live*: about 4 `web_media_seek` a second
   while a thumb drags, then a final one on release. If an injection is still running when
   the next `to` arrives, drop the older target and apply the newest — a queue of stale
   seeks is what scrubbing stutter is made of. Volume arrives at up to 8/s and is cheap
   enough to apply as it comes.
4. **Advertise `web_media_unit`** in `hello.features` once 1–3 are true. That is the phone's
   signal to stop inferring.
5. **Log the raw args** of every `web_media_*` call for one build (`to=…`, `percent=…`, and
   what the read script returned). The phone side is now unambiguous; the log is how the PC
   side stays that way.

**Self-test, no phone needed.** Pause a YouTube video at a known time and send
`web_media_get` from `tool/remote_probe.dart` (or any WebSocket client). At 12:34 of a
45:12 video the reply must read:

```json
{"found":true,"playing":false,"position":754000,"duration":2712000,
 "volume":100,"muted":false,"canFull":true,"seekable":true,
 "unit":"ms","volumeUnit":"percent"}
```

Then `web_media_seek {"to": 60000}` → the page is at 1:00. `{"delta": -10000}` → 0:50.
`web_media_volume {"percent": 10}` → the site's own slider shows 10%.

**Why the phone still works while you do this:** `WebMediaInfo.from` (`lib/core/models.dart`
in the phone repo) reads the units off the reply — a fractional number can only be
`currentTime` in seconds, a whole number is milliseconds, an explicit `unit` outranks both,
`web_media_unit` outranks the inference — and `SaluClient` writes back in the same dialect
it heard. Volume is written as percent regardless, because §17.11 already said so. That is
a bridge, not the design: once A1 lands, the inference has nothing left to do.

## A2. Find the page's real player, not its advert

`remote.md` §17.11's find rule was "the largest `video`/`audio` element in the top
document". On a real site that is often wrong: advert bumps, preview loops, hover-trailers
and the hidden element a player keeps warm are all `<video>`, and the biggest one is not
always the programme. When the phone drives the wrong element, every symptom in A0's list
appears at once — the clock is wrong, the seek "does nothing" (it moved a hidden clip), the
volume does not match the picture, and play/pause appears to work because *something*
paused.

Tighten the pick, in this order:

1. **Not paused and audible/visible first** — an element that is playing and has a box
   (`getBoundingClientRect()` with width and height > 0, not `display:none`, not
   `visibility:hidden`, `opacity > 0.05`) outranks everything.
2. Then the largest by `videoWidth × videoHeight`, falling back to the box size, falling
   back to `duration`.
3. **Ignore elements that cannot be the programme:** zero box, or a duration under two
   seconds (ident bumpers, looping backgrounds).
4. Keep the "remember nothing" rule — re-find on every command, so navigation never
   invalidates a handle.
5. Report what it picked in the read reply while debugging (an `el` description in the PC's
   log, not on the wire): tag, box, duration, paused. One log line ends every argument
   about which element a site exposed.

If the real player is inside a **cross-origin iframe**, nothing above helps and nothing
can: answer `found:false`, and the phone hides the controls with its one honest line. That
path already works — do not "improve" it into a guess.

## A3. `web_key` and `web_focus_get` — the D-pad (phone side: built)

The phone's Tune tab in Web mode is a D-pad. Today it can only draw ◀ ▶ (`browser_nav`)
because the PC does not advertise `web_key`; with the flag it draws the full cross, an Esc
chip, and — the part that makes it usable — a card naming whatever the page has focused.

Implement in the same injection path as the web-media bridge (`WebTab.executeScript`,
2-second timeout, errors swallowed, top document only):

1. **The focus order:** `a[href]`, `button`, `input`, `select`, `textarea`,
   `[tabindex]:not([tabindex="-1"])`, filtered to visible and not `disabled`, in document
   order. Current seat = `document.activeElement` (or seat 0 when it is `<body>`).
2. **`ArrowDown` / `ArrowUp`:** move one seat, `scrollIntoView({block:'center'})`, `focus()`.
   **Where a text field has the focus the arrows belong to the caret** — do not hop
   elements; report `editable:true` so the phone's line changes to say so.
3. **`Enter`:** `click()` on the focused element, or submit its form when it is an input.
4. **`Escape`:** exit element fullscreen, then page fullscreen, then close the topmost
   dialog. A couch remote with no Esc can leave the PC stuck in a full-screen advert.
5. **Draw the ring.** While a phone is connected and the mode is `web`, outline whatever
   has focus (a 2 px accent outline plus a soft glow, drawn by SALU over the WebView or by
   an injected style on the element — whichever the browser layer allows). §6.0 of the UI
   spec is blunt about this: *without the ring the user is steering blind and the feature is
   worse than useless.* It is part of the package, not a follow-up.
6. **Answer with the focus** in every `web_key` ack and in `web_focus_get`:
   `{focus:{label, tag, index, count, editable}}`, where `label` is the element's own text —
   `innerText`, else `value`, else `aria-label`, else `alt`, else `title`, truncated to 60
   characters — `tag` is the element name, and `index`/`count` are its seat in the order.
   The phone renders *Subscribe · BUTTON · 4 of 120*.
7. **Advertise `web_key`** in `hello.features`, and only when 1–6 are all true. A promised
   flag that answers `unknown_command` is worse than no flag: the phone draws the pad, the
   user presses ▲, and the pad then has to explain itself (it does, but it should not have
   to).
8. Unknown key names → `invalid_arguments`, not a silent ack.

**Honest limits stay honest:** this walks the page's own tab order, so it is exactly as good
as the site's markup. Canvas-drawn apps that manage focus themselves will not answer, and
nothing injected from outside can fix that. `found:false`-style honesty — report no focus,
let the phone say *Nothing focused yet* — beats a fake seat.

## A4. The tab strip mirror — list, switch, close, new (phone side: built)

The phone's nav row ends in a **tab door**: `▢ 3 tabs`. It opens a sheet with every tab's
title and URL, the live one marked, a ✕ on each row, tap-to-switch, and **New tab** at the
bottom. Behind `web_tabs` it is fully wired; without the flag it says *"This PC does not
report its tabs yet"* and still opens a URL. Nothing about it rides the snapshot — the
snapshot keeps its single scalar `web.tabs`.

**The refactor (§17.13.1).** The tabs live in `BrowserScreenState`'s private `_tabs` /
`_active`; §17.7 mirrored scalars around that. Now mirror the strip:

1. `BrowserService` gains a `List<WebTabMirror>` + `activeIndex` (`ValueNotifier`s, like
   `webTitle` and friends). `WebTabMirror` = `title`, `url`, `active`, `loading`, `hasMedia`
   — the values the tab bar already paints. **A mirror, not the controllers:** `WebTab`
   keeps owning its `WebviewController`.
2. Refresh it where the screen already calls `setStripTitle(...)`, plus on tab add / remove
   / select / title change / load start-stop. One place, one direction.
3. Writes come back through **one handler the screen installs**
   (`BrowserService.setTabHandler(...)`), exactly like `setNavHandler(...)` for
   `browser_nav`: activate = the screen's own tab select, close = the screen's own close
   (its confirmation, its session bookkeeping, its last-tab rule), new = the screen's own
   add-tab then navigate. **No second code path** — a remote that closes a tab differently
   from the ✕ on the strip is a bug nobody can reproduce.

**The verbs (§17.13.2).**

| Verb | Args | Reply | Errors |
|---|---|---|---|
| `web_tabs_get` | — | `web_tabs_result {tabs:[{index,title,url,active,loading,hasMedia}], active, count}` | `no_web_tabs` |
| `web_tab_activate` | `{index}` | `ack` | `tab_not_found`, `no_web_tabs` |
| `web_tab_close` | `{index}` | `ack` | `tab_not_found`, `no_web_tabs` |
| `web_tab_new` | `{url?}` | `ack {index}` — the new tab is active | `no_web_tabs`, `invalid_arguments` |

- `index` is the strip's own index at call time. A stale index answers `tab_not_found` —
  **never close the wrong page silently**, and never accept a negative or out-of-range one.
  The phone re-reads after every change, so a stale index self-heals in one round trip.
- Closing the **last** tab is the PC's existing decision and stays that way (whatever its
  own ✕ does). If that leaves Web mode, the snapshot's `mode` flips and the phone follows —
  it always has.
- `web_tab_new {url}` is the only "open" guaranteed to make a **new** tab. `open_url` and
  `browser_open` keep doing exactly what the PC's own Open-URL modal does; the phone uses
  `web_tab_new` when it can and `open_url` when it cannot, so both paths must work.
- **Advertise `web_tabs`** only when all four verbs and the mirror are in.

**Size discipline (§17.13.3).** The frame budget is 8 KB and a strip is a list of strings —
the one place this protocol can genuinely overflow. Cap the reply at **50 tabs**, truncate
`title` to 80 characters and `url` to 180, report the real total in `count`, and never send
favicons, histories or anything encoded. If it still would not fit, send fewer rows: the
phone renders what arrives and shows `count` as the truth. Add a unit test that builds a
200-tab strip and asserts the encoded frame is under 8 KB.

## A5. The bookmark mirror — read-only (phone side: built)

The phone's **☆ Saved pages** sheet has two piles: the browser's own bookmarks (read-only,
behind `web_bookmarks`) and SALU's URL library (already working — `library_get`,
`library_add`, `library_remove`, plus the sheet's **Save this page**, which writes the
current URL and page title into the library).

- `web_bookmarks_get` → `web_bookmarks_result {entries:[{name,url,folder}]}`. Read-only:
  a phone that can silently rewrite the PC's bookmark bar is a phone that can lose it.
  `folder` is one level deep, optional, and may be `""`.
- Cap **200 entries**, titles 80 / urls 180, same 8 KB rule and same test.
- **If the browser has no bookmark store, do not advertise `web_bookmarks`.** The phone then
  shows the library pile alone, which is already a complete saved-pages feature. An empty
  advertised pile is worse than an unadvertised one.
- No bookmark *writing* from the phone, and no bookmark sync into the URL library: two
  lists with one purpose is a design the user has to think about, and thinking is not what
  a couch remote is for.

## A6. Housekeeping that must not be skipped

1. **`hello.features`** gains, truthfully and only when implemented: `web_media_unit`,
   `web_tabs`, `web_bookmarks`, `web_key`. `proto` stays **1** — every verb here is
   additive, so an older phone and a newer PC keep talking, and a newer phone and an older
   PC keep talking with fewer buttons. That is the whole reason the flags exist.
2. **`RemoteErrorCode`** (the PC's `remote_protocol.dart`) gains `no_web_tabs`,
   `tab_not_found`, `no_web_bookmarks`. The phone's copy of that file was deliberately
   **not** edited — it is marked *COPIED FROM THE SALU PC REPO — DO NOT EDIT SEPARATELY*,
   and the phone's user-facing strings live in `lib/core/error_copy.dart` instead. Once the
   PC's copy changes, mirror it into `salu-remote/lib/protocol/remote_protocol.dart` in the
   same sitting, header comment and all.
3. **The phone's copy of the spec is already updated**: `remote.md` §17.4 (units + the six
   new verbs), §17.7 (pointer to §17.13), §17.8 (the three new error codes), §17.9
   (acceptance steps 23–28), §17.11 (units, element choice, coalescing) and the new
   **§17.13**. If the PC repo keeps its own copy of any of those, sync it from here rather
   than rewriting it.
4. **Rate limits unchanged:** 30 cmd/s per device. Live seeks (≈4/s) plus the 1/s read plus
   the 500 ms `hasMedia` find-script stay well inside it, but the `web_media_get` handler
   must not block the command isolate for 2 s at a time — the injection runs on the
   browser's isolate/queue, and a slow page must answer `busy` rather than stall the strip.

## A7. Tests to add on the PC side

| File | Covers |
|---|---|
| `test/remote_web_media_test.dart` | The unit conversions both ways (ms ↔ `currentTime`, percent ↔ `el.volume`); `NaN`/`Infinity` → `0` + `seekable:false`; `to` clamping at both ends; `delta` from the current seat; seek coalescing (three `to`s in a beat → one injection, the newest) |
| `test/remote_web_find_test.dart` | The element pick: a playing visible element beats a larger hidden one; sub-2-second and zero-box elements are ignored; a cross-origin-iframe page answers `found:false` |
| `test/remote_web_tabs_test.dart` | The mirror follows add/remove/select/title changes; a stale index → `tab_not_found`; a negative index → `invalid_arguments`; 200 tabs → ≤ 50 rows and an encoded frame under 8 KB; `count` still tells the truth |
| `test/remote_web_focus_test.dart` | The focus order and its filters; text-field caret mode (`editable:true`); `Enter` clicks vs submits; `Escape` order (element → page → dialog); the ack's `focus` payload shape |

## A8. Acceptance checklist (verify on the user's PC, in this order)

1. YouTube, paused at a known time → **long-press the phone's page card** → the diagnostics
   sheet's raw reply shows `position`/`duration` in ms matching the visible clock, `volume`
   as a percent, `seekable:true`, `unit:"ms"`; the phone's `Units read` line says
   `time ms · volume %` and its clock matches the page's own.
2. Drag the phone's seek bar → the picture scrubs **while the thumb moves** and stays where
   it was released; no snap-back, no jump to the end, no stutter.
3. Drag the volume to 10% → the site's own slider reads 10% and the sound follows the
   thumb. Mute → the site mutes. Neither ever touches the Windows volume.
4. −10 s twice in a beat → the page is 20 s back, not 10.
5. A live stream (no duration) → the phone shows *Live / not seekable* and greys the two
   nudges; nothing throws on the PC and no `NaN` reaches the wire.
6. A page whose player is an advert or a hidden clip → the controls now drive the programme
   (A2). A page whose player is in a cross-origin iframe → `found:false`, the phone's one
   honest line, and the nav shape still works.
7. With `web_tabs` advertised: the tab door lists the strip exactly as the PC's own tab bar
   shows it; tap switches the PC's page; ✕ closes and the list shrinks in place; closing the
   last tab does whatever the PC's own ✕ does; **New tab** with a URL opens a *new* tab on
   that URL. Kill a tab on the PC while the phone's sheet is open → the next read is right,
   and a stale index answers `tab_not_found` rather than closing a neighbour.
8. Without `web_tabs`: the same door says what is missing and still opens a URL.
9. ☆ → **Save this page** puts the current URL into the URL library under the page title
   (it shows up in Browse → Streams and on the PC); tapping a saved row opens it in the
   browser; with `web_bookmarks` advertised the browser's own bookmarks are listed above,
   read-only, and open the same way.
10. With `web_key` advertised: ▲▼ walk the page's focus, **the PC draws a ring on the
    focused element**, the phone's card names it (*Subscribe · BUTTON · 4 of 120*), OK
    clicks it, Esc leaves fullscreen / closes the dialog, and a text field reports
    `editable:true` so the phone's line changes. Without the flag: ◀ ▶ only, one line
    saying what is missing, and no dead button anywhere.
11. An older phone against the new PC: everything it knows still works, and none of the new
    verbs are reachable from it. `proto` never moved.

## A9. Order of work

| Step | Package | Why here | Rough size |
|---|---|---|---|
| 1 | **A1** units + `seekable` + clamping + `unit` + the `web_media_unit` flag | It is the reported bug, it is one file, and A0's diagnostics sheet says exactly which line to change | small |
| 2 | **A2** element pick | Same file, and it is the other half of "the controls do not do what I dragged" | small |
| 3 | **A4** tab strip mirror + the four verbs | The biggest ask (3 and 4 in the user's list) and the only real refactor | medium |
| 4 | **A3** `web_key` + `web_focus_get` + the ring | Independent of A4; the ring is the part that must not be skipped | medium |
| 5 | **A5** bookmark mirror | Read-only and smallest — or simply do not advertise it | small |

Each step is shippable on its own: the phone's doors are feature-flagged, so a PC that has
done step 1 and nothing else already fixes the user's first complaint, and the rest light up
as they land.

## A10. Before shipping the phone side (one honest caveat)

The phone changes were written in a sandbox with **no Flutter or Dart SDK**, so they have
not been compiled or run. They were checked by hand and by a structural pass, but the first
thing to do in `salu-remote` is:

```
flutter pub get
flutter analyze
flutter test
```

Files touched on the phone side (all of them, so an analyzer complaint has somewhere
obvious to live):

| File | What changed |
|---|---|
| `lib/core/models.dart` | `WebMediaInfo` reads the PC's units instead of assuming seconds; `WebMediaDialect`, `WebTimeUnit`, `WebVolumeUnit`; `WebTabInfo` / `WebTabPage` / `WebBookmarkInfo` / `WebFocusInfo`; `webBookmarksFrom`; `RemoteFeature` |
| `lib/core/client.dart` | `webMediaGet` / `webMediaRead` measure the dialect and reset it on `hello`; `webMediaSeek({Duration to, Duration delta})` converts on the way out; `webMediaVolume` stays percent; the new `web_tabs_*`, `web_bookmarks_get`, `web_focus_get` verbs; `supportsWebTabs` / `supportsWebBookmarks` / `supportsWebKey` / `supportsWebMediaUnit` |
| `lib/core/error_copy.dart` | copy for `tab_not_found`, `no_web_tabs`, `no_web_bookmarks` |
| `lib/ui/theme.dart` | `CommitSlider` deleted — `LiveSlider` is now the app's one slider |
| `lib/ui/web_body.dart` | live seek/volume bars with an optimistic hold, −10 s / +10 s, the tab door and the page doors, one poll in flight at a time, a fresh trial after navigation, long-press diagnostics |
| `lib/ui/web_sheets.dart` | **new** — the tabs sheet, the saved-pages sheet, the diagnostics sheet |
| `lib/ui/dpad.dart` | draws only the keys the PC answers, names the focused element, adds Esc and a focus re-read |
| `lib/ui/tune_tab.dart` | Web mode always shows the pad (the pad decides how much of itself to draw) |
| `test/web_media_test.dart` | **new** — the unit detection, the write-side conversion, equality, the tab/bookmark/focus parses |
| `remote.md`, `remote_apk_ui.md`, `README.md` | the contract and the specs, updated to match |

`flutter analyze` should come back clean; if it does not, the likely candidates are the two
newest language features in use — the wildcard parameters in `separatorBuilder: (_, _)`
(already used in `lib/ui/streams.dart`, so the SDK supports them) and `covariant` in
`WebBody.didUpdateWidget`. Nothing in the change needs a new dependency, so `pubspec.yaml`
is untouched and `flutter pub get` is a formality.

Then the manual pass, in the phone repo's own words: `remote.md` §17.9 steps **18–20**
(unchanged) and the new **23–28**. Steps 23 and 24 pass against today's PC as soon as the
phone is rebuilt, because the phone now reads whatever units the PC speaks — that is the
point of the fallback. Steps 25–27 wait on A3–A5, and each shows its honest line until then.

---

## Part A — implementation record (2026-09-24)

Done in this repo (the phone side is `salu-remote`; this record covers the PC):

| A | Package | Where it landed |
|---|---|---|
| A1 | units + `seekable` + clamping | `remote_web_media_bridge.dart` — the read script converts `currentTime`→ms and `volume`→percent at the script edge, sanitizes `NaN`/`Infinity` to `0` + `seekable:false`, stamps `unit:"ms"`/`volumeUnit:"percent"`, and the seek/volume scripts clamp instead of rejecting. `RemoteWebMediaResult` parses ints and re-defends the sanitization in Dart. |
| A2 | element pick | `remote_web_media_bridge.dart` — the shared find body prefers a playing, audible, visible element, then largest by `videoWidth×videoHeight` (box, duration), ignores zero-box/sub-2-second/hidden elements, re-finds every command, and stamps an `el` description for the log (`remoteWebMediaElLog`, `_webMediaGet` prints it). |
| A3 | `web_key` + `web_focus_get` + ring | `remote_web_focus_bridge.dart` (pure script builders + `RemoteWebFocusBridge` adapter), registered through `BrowserService.remoteFocusScript` from the active tab in `browser_screen.dart`; handler verbs in `remote_command_handler.dart`. The key script injects the 2 px accent ring page-side on every answer. |
| A4 | tab-strip mirror + four verbs | `browser_service.dart` (`WebTabMirror`, `webTabs`, `setTabHandler`, `remoteTabAction`); `browser_screen.dart` refreshes the mirror on add/remove/select/title/media (and installs the one write path); `remote_command_handler.dart` answers `web_tabs_get`/`web_tab_activate`/`web_tab_close`/`web_tab_new` with 50-row / 80-title / 180-url / honest-`count` caps. |
| A5 | bookmark mirror | `remote_command_handler.dart` `web_bookmarks_get` — read-only over `WebFavouritesService`, 200-entry / 80-title / 180-url / one-level-`folder` caps, no write verb exists. |
| A6 | housekeeping | `web_media_unit`/`web_key`/`web_tabs`/`web_bookmarks` advertised in `hello.features` (`RemoteService._helloFeatures`); `proto` stays **1**; `no_web_tabs`/`tab_not_found`/`no_web_bookmarks` added to `remote_protocol.dart` (mirror into the phone's copy); the repo's own `remote.md` §17.3 file map updated. |
| A7 | tests | `test/remote_web_media_test.dart` (units both ways, NaN/Infinity, clamping, delta, pick), `test/remote_web_find_test.dart` (pick: playing-vs-hidden, bumper/zero-box, cross-origin honesty), `test/remote_web_tabs_test.dart` (mirror, verbs, stale/negative index, 200-tab 8 KB, bookmarks), `test/remote_web_focus_test.dart` (order + filters, caret mode, Enter click/submit, Escape order, payload shape). |
| A8 | acceptance checklist | Recorded in this file (the 11 steps above) — to be run on the user's PC with the phone connected, in the given order. |
| A9 | order of work | Followed: A1 → A2 → A4 → A3 → A5. |
| A10 | phone first | Run `flutter pub get` / `flutter analyze` / `flutter test` in `salu-remote` before shipping — this sandbox has no Flutter SDK, so the phone side is still uncompiled. |

**Not done here (by design), and honest about it:** the tab/bookmark/focus handshake is
verified by unit tests against the bridge + handler seams, but the live page behaviours
(driving a real YouTube video, the ring on a real site, Esc out of a real advert) are on
the A8 manual checklist — they need a Windows WebView2 build and a paired phone. The two
temporary §10 pill-instrumentation `debugPrint`s in `playlist_panel.dart` and the
remote-pill bookkeeping are left in place until the live pill check on the user's PC
closes §10, exactly as §10's own plan asked.

---

# Part B — the `fs_places` drive scan, the group-by pill and channel grouping (2026-09-22)

> Kept exactly as written. §12 is a record of phone-side work, not a work order.

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
