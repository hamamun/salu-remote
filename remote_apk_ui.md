# SALU Remote — APK Interface Design (v2, expanded scope)

**Status:** 🎨 Design reference. The APK is a separate project, built later.
**Companion:** `remote.md` — the PC side. Its **§17** lists exactly what the PC must
add for everything described here.
**Supersedes:** the v1 layout of this file (5 screens) — the scope grew, so the
architecture changed. The rules and the visual language carried over unchanged.

---

## 1. What changed, and the one sentence that still decides everything

The first version made the phone a plain transport remote. You have now added four
things that all live **on the PC** — the file system, the stream library, the equalizer,
and the subtitle engine — plus the Player/Web mode pair.

> **The phone is a normal person's remote control for the PC.**
> It never plays anything itself, never holds its own truth, and never requires the user
> to walk over to the keyboard.

That last clause is the new work. Every feature you added exists for one reason: **so you
never have to get up.** Judge every design decision against that.

**Everything still out of scope:** playing media on the phone, screen preview, album art
or thumbnails over the network, delete/rename/move of files, and any cloud account.

---

## 2. The new shape: three tabs, by intent

The v1 design (Connect · Remote · Queue · Send · Settings) was built for transport only.
With EQ, subtitles and a file browser added, one scrolling page would become a junk
drawer. So the app is now **three tabs, grouped by what the user is doing** — not by which
data source they came from:

```
┌──────────────────────────────────────────────────────────┐
│  PLAY              BROWSE                    TUNE        │
│  the everyday      find something to play    adjust what │
│  remote            · Files (PC drives)       is playing   │
│  · transport       · Streams (M3U + URL)     · Equalizer  │
│  · now playing     (one segmented switch)    · Subtitles  │
│  · volume                                    · Audio      │
│  · mode pill                                 (segmented)  │
│  · queue card                                            │
└──────────────────────────────────────────────────────────┘
```

- **Play** — 90% of all use. One thumb, no scrolling needed in Focus mode.
- **Browse** — "Files" and "Streams" are the same user intention (find something), so they
  share a tab with a segmented switch at the top. This keeps the bottom bar at three items.
- **Tune** — Equalizer, Subtitles and Audio are all "change what is happening right now",
  and all three are meaningless when nothing is playing. Keeping them together lets the
  tab say *"Nothing is playing"* in one place. The word **Tune** is borrowed from SALU's
  own left/right panel, so the two apps share vocabulary.

**The mini now-playing strip.** On **Browse** and **Tune**, a slim strip sits just above
the bottom bar:

```
│ ▶  Big Buck Bunny        12:34 / 45:12   ⏸ │
```

Tap it → jump to **Play**. The pause button works without leaving the screen. This one
strip removes most of the reason to switch tabs mid-movie.

### 2.1 What each mode offers (added 2026-09-20)

The three tabs are not equally available in both modes, and pretending otherwise
produces buttons that do nothing:

| Tab | Player mode | Web mode |
|---|---|---|
| **Play** | transport · volume · queue | page nav · the page's own player (§4.2) |
| **Browse** | Files · Streams | **disabled** — greyed, with the reason on tap |
| **Tune** | Equalizer · Subtitles · Audio | **a mouse pad** (§6.0) |

**Browse is Player-only** because opening a PC file pulls the PC straight back to
Player mode anyway (D8) — the tab would only ever bounce the user. It greys out
rather than vanishing, so the bar does not reshuffle under the thumb, and tapping
it says why. Switching into Web mode while Browse is up moves the user to Play.

The **mode switch shows both seats** — `Player` and `Web` side by side, not one
pill that toggles. You should be able to see where you are going before you go.

**Connect** stops being a screen most of the time: it is a **sheet** that slides up only
when a connection is missing or the user taps the header. First launch = the Connect
sheet; every launch after that = straight to Play, already connected.

---

## 3. The space system — how showing/hiding actually works

You asked for show/hide. Space is the scarcest thing on a phone, so there are four
separate mechanisms, in this order of importance:

**1 · Focus mode (the big one).** A chevron in the header collapses the Play tab to the
bare essentials — the remote you can use with your eyes closed:

```
┌──────────────────────────┐         ┌──────────────────────────┐
│ ● Living Room PC  ⌄  ⋮  │         │ ● Living Room PC  ⌃  ⋮  │
├──────────────────────────┤         ├──────────────────────────┤
│ Big Buck Bunny           │         │ Big Buck Bunny           │
│ ███████░░░░░░░  12:34    │   ⌄     │ ███████░░░░░░░  12:34    │
│                          │  ───▶   │                          │
│ ⏮   ⟲10   (▶)   ⟳10   ⏭ │         │ ⏮   ⟲10   (▶)   ⟳10   ⏭ │
│                          │         │                          │
│ 🔊 ███████░░░░   80      │         │ 🔊 ███████░░░░   80      │
├──────────────────────────┤         ├──────────────────────────┤
│ [Queue]  [Subs]  [EQ]    │         │ (everything else hidden) │
└──────────────────────────┘         └──────────────────────────┘
   expanded (default)                    focus mode
```

Focus mode is remembered per device, and the chevron is the only way back.

**2 · Settings → Play screen (the permanent version).** A checkbox list of every optional
element, so a user who never touches EQ never sees it again:

```
Settings → Play screen
  [✓] Volume row              [ ] Tune tab
  [✓] Mode pill (Player/Web)  [ ] Streams segment
  [✓] Shuffle & repeat row    [ ] Subtitles card
  [✓] Queue card              [ ] Speed chips (in Tune → Equalizer)
  [✓] Mini now-playing strip on Browse / Tune
```

Defaults: everything on **except** nothing — ship with everything visible, and let people
subtract. (Hiding a *tab* hides it from the bottom bar entirely; the app never ships with
fewer than two tabs.)

**3 · Collapsible sections inside every tab.** Every card header (`Queue · 12 items ⌄`,
`Presets ⌄`, `Sync ⌄`) is a tap-to-collapse row. Collapsed/expanded state is remembered
per section. This is what keeps the Tune tab usable on a small phone.

**4 · The list itself is space.** In the file browser the settings row
(`Media only · Sort · Hidden folders`) collapses behind a small filter icon, because it is
set once and never touched again.

---

## 4. Tab 1 — Play

### 4.1 Player mode (the PC is playing)

```
┌──────────────────────────┐
│ ● Living Room PC  ⌄  ⋮  │ ← header: dot · name · focus · overflow
│              ◐ Player    │ ← MODE PILL (mirrors the PC, tap = switch)
├──────────────────────────┤
│  Big Buck Bunny          │
│  ┌────────────────────┐  │
│  │███████░░░░░░░░░░░░░│  │ ← seek: fires *while* dragging (throttled),
│  └────────────────────┘  │    final value on release
│  12:34            45:12  │
│                          │
│  ▶  ⏹  ⏮  ⏭  ⟲10 ⟳10 ⛶ │ ← one row, one style, one size (user,
│                          │    2026-09-22): play/pause · stop · previous ·
│         ⟳     ⤨  (⟲)     │    next · −10 s · +10 s · fullscreen
│                          │ ← repeat · shuffle — icon-only row — plus
│                          │    START OVER (⟲) while the PC offers it
│  🔊 ███████░░░░   80     │ ← mute lives here, left of the slider — once
├──────────────────────────┤
│ ▾ Queue · 12 items     ✕ │ ← collapsible card · clear button · 5 rows max
│   3  Episode 2.mkv       │ ← the whole playlist scrolls inside and
│ ▶ 4  Episode 3.mkv       │    auto-scrolls so the current row stays in view
└──────────────────────────┘
```

- **Mode pill** sits on the header line: `◐ Player` / `◐ Web`. It is a *label and a
  switch* — it always shows the PC's real mode (the PC drives it), and tapping it asks
  the PC to switch. When the PC switches on its own, the pill animates to the new label.
- **Every control is an icon at one size (user, 2026-09-22).** The transport row is
  play/pause · stop · previous · next · −10 s · +10 s · fullscreen, all the same plain
  icon button — no filled play button, no text chips (the old Stop chip is a seat in
  this row). Repeat and shuffle sit below on their own icon-only row — repeat shows
  `repeat_one` when repeating one and lights with the accent whenever it is on. Mute
  sits at the left of the volume slider and nowhere else (it used to be doubled: chip
  *and* slider row).
- **Start over `⟲`** (user, 2026-09-22) is a **conditional third seat of the repeat ·
  shuffle row**, and it is not a phone invention: it mirrors the PC's **Resume toast**.
  The PC shows that toast when an item lands at a remembered position — *"you resumed at
  12:34 — Restart?"* — and it lives 4 seconds (or until Esc, a click-outside, or any
  transport action). While it is up, `playback.resume` carries `{"position":754000}`
  (`remote.md` §17.4/§17.5) and the seat appears, showing the same clock in its tooltip;
  the moment the toast closes the field goes `null` and the seat goes with it — **the seat
  never outlives the toast and never appears without one**, on either screen. Tap =
  `restart` (the toast's own Restart word-action: `0:00` and play, which also closes the
  toast). Plain `Icons.replay` — `replay_10` beside it already owns the "−10 s" reading,
  and the accent tint marks it as live rather than decorative. Icon-only, like every other
  control in that row (user, 2026-09-22).
- **Seek and volume sliders are realtime (user, 2026-09-22):** they stream throttled
  updates *while* the thumb moves (≈8/s — inside §8's budget) and send the final value
  on release, instead of one command on release only. **The Web body's bars follow the
  same rule (2026-09-23, §4.2)** — a seek bar that only fires on release feels broken
  next to one that does not, and the page's player is the one place the phone reads
  position slowly enough (1/s) to need the optimistic hold §8 describes.
- **Queue is the playlist** (user, 2026-09-20): a collapsible card that shows **at most
  5 rows** and scrolls inside whenever there are **more than 5 items** — the whole
  queue is fetched, 100 rows per `queue_get` call (user, 2026-09-22) — and
  **auto-scrolls so the now-playing row stays in view** the moment the track changes.
  Tap a row to jump to it. The **✕ in the header clears the playlist** (user,
  2026-09-22): confirm → `queue_clear` → the PC stops and empties the queue (§17.4).
  It never pushes the transport controls off-screen.
- **Queue header, search and favourites (user, 2026-09-23):** the header mirrors the
  PC panel's header — the **search bar sits beside Queue** with its count (`14`, or
  `9 / 14` while a filter thins the list) and its **✕ clear button inside it** (only
  while there is text), and the **bookmark sits beside the clear button** (channels
  only). Typing filters rows by title and flattens grouped modes until it clears (the
  PC's §10.3 rule); channel rows carry the PC's bookmark (solid when saved, dim
  outline otherwise) and the header bookmark shows only favourite channels, in a flat
  list without group heads. Favourites are kept on the phone by title — the phone never
  holds the PC's stable channel keys.
- **Channel grouping is the PC's accordion (user, 2026-09-23):** in a grouped mode
  every head paints but only the open group's channels do (autohide) — a head tap
  toggles, it never plays, and the group holding the playing channel opens on its own
  at every mode choice and track change, exactly like the PC panel. By default every
  head stays collapsed and only the played channel's group is expanded; while the
  heads load the list waits instead of flashing the full flat list. The total channel
  count sits beside Queue in the header (`Queue · 1234 channels`) and again inside
  the search bar, with each head carrying its own group count.
- **Channel mode greys transport (user, 2026-09-23):** while an m3u is loaded the
  **−10 s / +10 s seeks** answer the snapshot's `seekable` (false for channels — a
  live stream has no position) and **repeat · shuffle stay greyed out** (the PC drops
  both in channel mode), instead of sending commands the PC would only ignore.
- **Activity dot:** during any long PC job (folder read, subtitle search or download,
  queue page), a small dot pulses once next to the connection dot — appearing only after
  300 ms, so quick jobs never make it flicker. One dot, no text (user: "do what is best").

### 4.2 Web mode (the PC is in its browser)

The **same tab, transformed** — because the mode *is* the same remote, pointed at a
different thing. And it has **two shapes**, because of the rule the user added
(2026-09-20): *when the page itself is playing media, only the basics are offered* —
play/pause, seek bar, volume, mute, fullscreen — because that is all most online
players expose anyway.

**Shape 1 — the page has a player** (`web.hasMedia`, mirrored from the PC):

```
┌──────────────────────────┐
│ ● Living Room PC  ⌄  ⋮  │
│               ◐ Web      │
├──────────────────────────┤
│ ⌂  ◀  ▶  ⟳  ⛶            │ ← nav row: Home · Back · Forward · Reload · Fullscreen
│  [＋ New tab] [☆ Saved]  │ ← the page doors (§4.2 below)
│  Dune — YouTube          │ ← title (tap = URL box · long-press = diagnostics)
│  ┌────────────────────┐  │
│  │███████░░░░░░░░░░░░░│  │ ← the PAGE's position, live while dragging
│  └────────────────────┘  │
│  12:34            45:12  │
│                          │
│   ⏪10     ( ▶ )    10⏩   │ ← the one big button, with the two nudges
│                          │
│  🔊 ███████░░░░    🔇    │ ← the page player's own volume + mute
│  ⌄ Open tabs      3 tabs ＋│ ← the open-tab section, collapsible (§4.2)
└──────────────────────────┘
```

**Shape 2 — no media on the page** (`found:false`): the nav body — the same nav row
(home · back · forward · reload · fullscreen), the page doors, the live tab title/URL card,
"Open a URL on the PC", and the same open-tab section at the foot. No volume slider (there
is nothing to volume) — that row simply isn't there. A page that reports no length (a live stream) keeps the shape but swaps the bar for
one line, *Live / not seekable — this page does not report a length.*, and greys the two
nudges: the same rule the Play tab follows on `playback.seekable`.

**The page doors** (added 2026-09-23, revised 2026-09-24) — navigation, not playback, so
they sit in *both* shapes:

| Door | Opens | Needs from the PC |
|---|---|---|
| **⌂ Home** (nav row, first seat) | the loaded page goes to **its own site's front page**, in the same tab — a YouTube video page goes to youtube.com, like SALU's own home button | `browser_nav {action:"home"}` (`web_home`); an older PC gets `browser_open` with the page's own origin instead. Grey when the page has no origin (`about:blank`, a local file) |
| **⛶ Fullscreen** (nav row) | **one** seat, and the PC decides the target: the page's own player when the page has one, the SALU window when it has not. The mark shows what actually happened | `web_fullscreen` (§17.14.1). This replaced the old split — which made YouTube do nothing and every other stream fullscreen the whole app |
| **Open tabs** (a section at the foot of the body, under the volume row) | every open tab: title + URL, the live one marked, a ✕ on each, tap to switch, ＋ for a new tab. **Collapsible, with the state remembered** — exactly the queue card's shape | `web_tabs`; without it the section says so in one line (no count — a "0 tabs" beside "does not report its tabs" would be a small lie) and its ＋ still opens a URL. With it, the count comes from the snapshot's own scalar until the first list arrives, so it is right before anything is fetched |
| **＋ New tab** (doors row) | the URL box — clipboard pre-filled as always, and a typed address is given `https://` before it is sent (`lib/core/web_url.dart`, the blank-tab fix) | `web_tab_new {url}` when the PC has it, `open_url` otherwise (which already routes into the browser in Web mode) |
| **☆ Saved pages** | **the PC browser's bookmarks, and nothing else**; *Save this page* appends the page being looked at (to the browser's bookmarks with `web_bookmark_add`, else to SALU's own list, and the snackbar says which). Tap = open on the PC | `web_bookmarks`; without it the sheet says the PC does not report bookmarks yet and the save still works |
| **long-press the title card** | Web diagnostics: what the PC reported, in its own numbers, next to what the phone made of them | nothing — it is the phone's own glass, and it is how a units question gets settled by looking |

**Why the tabs are a section and not a sheet** (user, 2026-09-24: *"i need that thing will
show below volume bar and there will be heading 'open tab' just like queue for normal player
and will have collapse/expand option like queue"*): switching tabs means looking at *another
page*, and a sheet covers the page you are about to look at. The section leaves the page card
and the controls visible, costs zero pixels when collapsed, and is the same row-panel the user
already knows from the Queue. **SALU's own m3u list no longer appears in the saved-pages
sheet** — the user's own verdict: *"m3u which is player part should not appear in that list"*.

Closing a tab asks nothing, the way a browser does not; the PC keeps its own session
history and its own last-tab rule.

Shared rules:

- The transport rows **disappear** in both shapes instead of sitting there dead. Dead
  buttons are the fastest way to make an app feel broken.
- **Web-media controls drive the page's own player** (JavaScript on the PC side — see
  `remote.md` §17.11), not mpv. The volume slider is the site's own volume; it never
  touches the Windows volume. The bars are **live**, like the Play tab's own, and the
  numbers on the wire are the PC's — milliseconds and integer percent per `remote.md`
  §17.4, with the phone reading the units off the reply until the PC promises
  `web_media_unit`. A wrong unit here is invisible in every other control and total in
  these two, which is why the diagnostics sheet exists.
- **When the page's player cannot be reached** (player inside a cross-origin iframe, or
  DRM), the phone shows one plain line — *"This site's player can't be controlled from
  outside."* — and drops back to the nav shape. Hidden beats broken, every time. That
  verdict belongs to **the page**, not to the session: navigating anywhere (the URL box, a
  tab switch, the PC user clicking something) gives the next page a fresh trial.
- **The open tabs are a section, not a button** (user, 2026-09-24). The list, the switching,
  the closing and the new tab are built on the phone and specified for the PC in `remote.md`
  §17.13; the section is collapsible and remembers its state like the queue card, and until a
  PC advertises `web_tabs` it says what is missing and its ＋ still opens a URL. The downloads
  shelf stays PC-only — nothing a couch user would do with it.
- **"Open a URL on the PC"** is the sleeper feature of this whole app: type or paste on
  your phone, the PC browser goes there. Available in both shapes (tap the title in
  Shape 1).
- Switching back: tap the pill, or the PC user does it themselves — the APK follows either
  way, with a 200 ms cross-fade between the bodies.

---

## 5. Tab 2 — Browse

Segmented switch at the top: **Files | Streams**.

### 5.1 Files — the PC's drives

```
┌──────────────────────────┐
│ ● Living Room PC  ⌄  ⋮  │
├──────────────────────────┤
│   Files   │   Streams    │
├──────────────────────────┤
│ ◀  C: › Movies › Action  │ ← breadcrumb, tap any crumb
│ ┌──────────────────────┐ │
│ │ 📁 ..                │ │
│ │ 📁 2024           > ＋│ │ ← folder: ▶ plays it, ＋ queues it
│ │ 📁 Extras         > ＋│ │
│ │ 🎬 Dune.Part.One. > ＋│ │ ← tap = PLAY NOW · ＋ = add to queue
│ │ 🎬 Alien.mkv 2.2G > ＋│ │    (▶ only on media rows)
│ │ 📄 notes.txt         │ │ ← non-media: visible if filter off,
│ └──────────────────────┘ │    never tappable, no quick marks
│  ⋯ 480 more       ⚙filters│ ← paging + filter/sort icon
└──────────────────────────┘
    long-press anywhere → select mode ☑
```

**Pinned places** replace the boring drive list as the landing view — this is the single
biggest usability win in the whole browser:

```
│  Quick places            │
│  [▶ Now playing] [⬇ Downloads] │
│  [🎬 Videos] [🎵 Music] [🖥 Desktop] │
│  Drives                  │
│  [ C: ] [ D: ] [ E: ]    │ ← the PC's real local drives only — network letters are never listed
```

`Now playing` opens the folder of the file currently playing on the PC, so the next
episode is always two taps away (SALU already knows that folder).

**Hard rules for this screen** (they matter more than the layout):

| Rule | Why |
|---|---|
| **Read-only. Forever.** No delete, no rename, no move, no new folder. | A phone-thumb slip must never be able to destroy a library. |
| **Media-only filter ON by default.** The filter icon reveals other files, but only media files are ever tappable-to-play. | Folders like `C:\Windows` become harmless. |
| **System folders hidden by default** (`Windows`, `Program Files`, `ProgramData`, `$Recycle.Bin`, `System Volume Information`, `AppData`, `node_modules`…), behind one "Show hidden/system" toggle. | Prevents an accidental 40-second wait on a 90 000-entry folder. |
| **Paged: 200 rows, then "load more".** | Never block the phone on a giant directory listing. |
| **No thumbnails or posters — ever, in v1.** Names, sizes, icons. | Images over the socket is a whole feature; it would make this the slowest screen in the app. |
| **The file never travels.** The PC opens the path locally. | The whole point: a 40 GB file plays in one byte of network traffic. |
| **Multi-select, decided (user, 2026-09-20).** Every media/folder row carries two small quick marks — **`▶` play now** and **`＋` add to queue** — so one item never needs a long-press. **Long-press anywhere → select mode:** checkboxes appear, the header becomes `N selected` with a **Select all ⇄ Deselect** toggle, and a bottom bar appears with `▶ Play N` · `＋ Queue N` · `✕ done`. | Pick tonight's three episodes in two taps. The PC caps one batch at 500 paths (`remote.md` §17.4). |

### 5.2 Streams — saved M3U URLs and a URL box

```
├──────────────────────────┤
│   Files   │   Streams    │
├──────────────────────────┤
│ ┌──────────────────────┐ │
│ │  ＋  Add a URL     │ │ ← accent; paste box + "Save on the PC too"
│ └──────────────────────┘ │
│ Saved on the PC          │
│ ┌──────────────────────┐ │
│ │ ● BDIX IPTV       ▶  │ │ ← ● = UrlHealth (green/red/grey)
│ │   http://10.0.0.5…   │ │    tap = load + play on the PC
│ ├──────────────────────┤ │
│ │ ● Sports m3u8     ▶  │ │
│ └──────────────────────┘ │
│ (this is the PC's own list — currently capped at 7) │
└──────────────────────────┘
```

- The list is **the PC's `UrlLibraryService`, mirrored** — never a second list on the
  phone. Add from the phone and it appears on the PC; the health dot is the PC's verdict.
- **Add a URL** takes anything: a direct stream, a YouTube link, an `.m3u` URL, or a plain
  web link (which plays in Web mode instead — the PC already classifies this in
  `OpenMediaService` / `ChannelSource`).
- **Paste detection:** if the clipboard holds a URL, the field pre-fills and the button
  reads `Play this link`. Typing on a phone keyboard is the tax this screen exists to
  avoid.
- Long-press a saved row → `Play now · Rename · Delete` (these edit the PC's library, which
  is the user's own list — deletion is allowed *here*, unlike files).

---

## 6. Tab 3 — Tune

Segmented: **Equalizer | Subtitles | Audio**. All three show *"Nothing is playing"* (with
a Play shortcut) when the PC has no media. **In Web mode none of the three exist** — mpv
is not in the picture — and the tab becomes a **mouse pad** instead (§6.0).

### 6.0 Web mode — the tab becomes a mouse pad (rewritten 2026-09-24)

> **This replaces the D-pad.** The user, after using the D-pad on real sites: *"i need to
> remove this and everything. after removing it will be mouse pad as laptop has a nice
> bounding box will be shown which will be track pad. by touching there will activate mouse
> at salu and double tap will be enter. below track pad will be simple one line."*
> So: no arrows, no OK, no Esc chip, no focus card, no explanation — **a trackpad and one
> line**. The `web_key` verbs (`ArrowUp` / `ArrowDown` / `Enter` / `Escape`) stay in the
> protocol; the pad simply uses `Enter` for its double tap, and the PC keeps its focus ring.

In Web mode there is no equalizer, no subtitle track and no audio track to choose. What there
*is* is a web page the user cannot reach from the couch — so the tab hands them **the PC's own
pointer**, which is the thing that can reach everything on it.

```
┌────────────────────────────────┐
│                                │
│          the trackpad          │ ← drag here; the PC's cursor follows
│       (round-cornered box)      │
│                                │
└────────────────────────────────┘
              Mouse                ← the one line, and nothing else
```

| Gesture | Does | Verb |
|---|---|---|
| drag | the PC's pointer follows the thumb, live | **`web_mouse_move {dx, dy}`** (new, `remote.md` §17.14.3) |
| single tap | left click, where the pointer already stands | **`web_mouse_click {button:"left", count:1}`** (new) |
| double tap | **Enter** — activate whatever the page has focused | `web_key {key:"Enter"}` (§17.13.5) — a double click when the PC has no `web_key` |

**The one line under the pad says `Mouse`.** That is the whole text budget of this tab. The
only time it says anything else is the honest one: when the PC has not advertised `web_mouse`
(or answered `unknown_command` for it), it reads *"Mouse needs an updated SALU on the PC"* —
still one line, still the same box in the same place. A pad that silently does nothing is the
one outcome worth a sentence; everything else is noise in front of a page.

**Why the gestures are these.** A trackpad's tap-to-click is the gesture the hand already
knows, and Enter is what a page's own focus model understands everywhere — YouTube's player,
a search box, a cookie banner's Accept. Their user asked for both by name.

**Nothing is drawn while the finger works** — no trail, no ripple, no coordinates. The
feedback is the PC's cursor on the PC screen, which is why the PC must keep that cursor
visible while the pad is in use (§17.14.3).

**Cost control.** Travel is batched on the phone: one packet per 40 ms (~25 commands a
second), at most two packets in flight, each clamped to ±320 px after a 2.5× gain. That sits
inside the PC's 30 cmd/s budget beside the 1/s web-media read, and a slow PC slows the
pointer instead of queuing stale movement behind it.

**Honest limits.** A mouse is exactly as good as the PC's ability to inject input. Where it
cannot (a locked session, a build without the input path) the pad says so in its line and the
user still has the Play tab's own controls. Nothing is faked.

**Implementation.** `remote.md` §17.14.3; the phone side is `lib/ui/mouse_pad.dart`, and
`lib/ui/dpad.dart` is deleted.

### 6.1 Equalizer

The PC's Tune panel has four lines — EQ, Picture, Aspect, Speed. **v1 sends the EQ line
and the Speed line** to the phone (Speed is right below); Picture and Aspect stay PC-only
(§11). The layout leaves room for the rest.

```
├──────────────────────────┤
│ Equalizer │ Subs │ Audio │
├──────────────────────────┤
│ ┌──────────────────────┐ │
│ │    (live curve)      │ │ ← port EqCurvePainter; redraws as you drag
│ └──────────────────────┘ │
│ ⤨ Flat · Rock · Jazz ›   │ ← horizontal preset chips, from the PC's own list
│ ⭐ My                    │ ← the PC's "My" slot: apply or overwrite
│ ──────────────────────── │
│ 31  63  125 250 500 1k   │
│ ▕▏  ▕▏  ▕▏  ▕▏  ▕▏  ▕▏   │ ← 10 vertical sliders, ±12 dB
│ 2k  4k  8k  16k          │
│                          │
│ [ Reset ]   Auto EQ  (●) │
│ Learned from what you keep │
└──────────────────────────┘
```

- **Presets are the PC's list, in the PC's order**, and the *set* is chosen by the PC:
  SALU already shows 13 audio presets for audio files and 4 video presets for video
  (`TuneService.fileKind`). The APK just renders whatever the PC sends — including "My"
  and the current selection — so the two can never disagree.
- **Ten vertical sliders beat a draggable curve on a phone.** Fat thumbs, no fine aiming:
  a slider can be grabbed anywhere along its height. The curve preview above gives the
  shape at a glance, so the sliders only need to be precise, not pretty.
- **Landscape, decided (assistant's call): yes — but only here.** Turn the phone sideways
  on the Equalizer and it becomes a mixing desk: curve + presets in a left rail, all ten
  sliders full-height on the right. Portrait already fits ten sliders (≈34 dp each); the
  landscape layout is precision for its own sake, and no other screen unlocks it.
- **Tuning while you drag:** the APK sends band changes continuously; the PC already
  coalesces them (`TuneService.eqWriteGap = 120 ms`), so no extra throttle is needed on
  either side. Send the whole 10-gain curve on release — never a diff.
- **Keep the curve in sync while Equalizer is open:** refresh from `tune_get` while this
  pane is active so PC-side preset, Auto EQ, and band changes appear on the phone. Do not
  replace a curve under the user's finger; fetch the PC's final curve when the drag ends.
- **Reset** = `Flat`. **Auto EQ** is a switch mirroring the PC's setting; the *learning
  memory* is intentionally not clearable from the phone (destructive + invisible).
- **Speed lives here too** (user's answer #5 → assistant's call: in, and at the bottom of
  this segment, keeping three tabs and three segments):

```
│ ──────────────────────── │
│ Speed                    │
│ [0.5×][0.75×][1×][1.25×] │
│ [1.5×][2×][3×]           │ ← the PC's own stops, verbatim
```

  These are the PC's real stop keys (`x0_5 … x3`), rendered as chips with the current one
  filled; tapping sends one `speed_set` and the PC's snapping does the rest. No fine slider
  — the PC deliberately has none either (this line is "not evenly spaced" on purpose). The
  chip row is included in the show/hide checklist like every other section.

> **Honest advice:** the EQ only makes sense when you can *hear* the PC — couch distance,
> not another room. So don't spend design effort making it buttery; make it precise and
> reversible. That is why the preset chips and `Reset` sit right next to the sliders.

### 6.2 Subtitles

```
├──────────────────────────┤
│ Equalizer │ Subs │ Audio │
├──────────────────────────┤
│ Tracks               ⌄   │
│ ┌──────────────────────┐ │
│ │ ● English (embedded) │ │ ← ● selected (mpv's truth, mirrored)
│ │ ○ off                │ │
│ │ ○ Bengali — local .srt│ │
│ └──────────────────────┘ │
│ Sync                 ⌄   │
│   [ −0.5s ]  0.0 s  [ +0.5s ] │ ← hold to repeat, 0.1 s steps
│   [ Reset ]                    │
│ ┌──────────────────────┐ │
│ │ 🔍 Search online…  │ │ ← opens the search screen below
│ └──────────────────────┘ │
│ ┌──────────────────────┐ │
│ │ 📁 Add a subtitle file│ │ ← reuses the Files browser (.srt/.ass/.sub)
│ └──────────────────────┘ │
│ Auto-download on play (●) │
└──────────────────────────┘
```

**Search online** — this is the PC's own OpenSubtitles engine, driven from the couch:

```
┌──────────────────────────┐
│ ← Subtitles              │
│ [ Dune Part One       ]🔍│ ← pre-filled with the PC's current title
│ Language [English ▾]     │ ← the PC's saved preference
│ ┌──────────────────────┐ │
│ │ English              │ │
│ │ Dune.Part.One.2021.1080p │
│ │ WEB · 584k downloads │ │ ← SubtitleResult.subLine, verbatim
│ │           [ Download ]│ │
│ ├──────────────────────┤ │
│ │ Bengali              │ │
│ │ …                    │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```

- **The PC downloads and applies.** The phone only asks and watches. Tapping *Download*
  is `saveAndLoad`: the file lands beside the media with SALU's own naming rule and is
  loaded immediately — the subtitle is on screen before your thumb leaves the phone.
- **Tapping a track row** = `selectSubTrack`; `off` = `SubtitleTrack.no()`. While
  Subtitles is open, refresh the PC's full track surface so its selected track and delay
  changes also appear on the phone; refresh immediately after a phone-side selection.
- **Track names and list height:** prefer the PC's human-readable language/name fields
  (for example English, Hindi, Spanish, or Mandarin), rather than repeating a generic
  `Track` label. Keep the list to five visible rows, scroll inside it when longer, and
  bring the selected embedded track (or `off`) into view automatically.
- **Sync** mirrors `PlayerService.subDelay` (0.1 s steps, hold to repeat, `Reset` = 0).
  This is the feature people reach for most often during a bad subtitle file.
- **Add a subtitle file** opens the Files browser in **subtitle mode** — same screen, same
  rules, but listing only `.srt/.ass/.sub/.vtt` and returning a path instead of playing it.
  One browser, two jobs; no second picker to build.
- **Auto-download on play** is a switch over the PC's existing setting.
- The Download action is enabled only when a fresh PC snapshot reports a configured key,
  signed-in engine, and no quota pause. Keep the best three results returned by the PC;
  the PC performs `saveAndLoad`, placing the subtitle beside the media and loading it.

### 6.3 Audio

A humble list, included because multi-track files are common and this is one screen of work:

```
│ Audio tracks             │
│ ┌──────────────────────┐ │
│ │ ● English · 5.1 AC3  │ │ ← ● = currently selected
│ │ ○ Hindi · 2.0 AAC    │ │ ← tap = switch (no confirmation)
│ └──────────────────────┘ │
```

The Audio pane mirrors the PC's selected track while open. Use the same five-row inner
viewport and selected-track auto-scroll as Subtitles; show the PC's language/name instead
of a generic track label when it is available.

---

## 7. What the phone cannot know — and must be told

Half the "it looks broken" bugs in a remote app come from state that only the PC has.
Every one of these must arrive in a snapshot and be rendered as **plain words**, never as
a silent failure:

| PC-only fact | What the APK shows |
|---|---|
| No media loaded | Tune tab: *"Nothing is playing"* + a Play shortcut |
| PC is in Web mode | Play tab shows the Web body (nav row · page doors · the page player's own controls); Tune tab becomes the mouse pad |
| **The PC has not been updated** — any of the web flags missing from `hello.features` (`web_tabs`, `web_bookmarks`, `web_key`, `web_media_unit`, and since 2026-09-24 `web_home`, `web_fullscreen`, `web_mouse`, `web_bookmark_add`) | Each door says so in one plain line and keeps working at the level every PC supports: the Open tabs section still opens a URL, Saved pages still saves into SALU's list, Home falls back to the page's origin, fullscreen falls back to the old split, the trackpad says one line, the media bars read the units off the reply. **Never a dead button** |
| The page reports no length (live stream, unloaded element) | No seek bar — one line, *"Live / not seekable — this page does not report a length."*, and the ±10 s nudges greyed with it |
| The page reports no focus | The pad's card reads *"Nothing focused yet"* with the ring hint, instead of a stale element name |
| OpenSubtitles **not signed in** | *"Sign in to OpenSubtitles on the PC to download subtitles."* |
| **Download quota** reached | *"OpenSubtitles download limit reached. Try again tomorrow."* |
| **No API key** configured | *"Add an OpenSubtitles key on the PC to search."* |
| **File browsing** is switched off on the PC | Files tab: *"File browsing is turned off on the PC."* + a hint where to turn it on |
| Search in progress | A determinate-looking progress row on the PC's behalf: *"Searching…"* (never a frozen button) |
| Download in progress | *"Downloading…"* then *"Loaded"* — and on failure, the PC's own reason |
| A path no longer exists | *"That file has moved or been deleted."* |
| **Web page's player is out of reach** (cross-origin iframe / DRM) | Web body drops to the nav shape with one line: *"This site's player can't be controlled from outside."* |
| **The PC's Resume toast is up** (an item landed at a remembered position) | The **Start over** seat appears in the repeat · shuffle row, tooltipped with the toast's own resumed-at clock — and disappears with the toast (§4.1). Never a phone-side offer of its own. |

---

## 8. Feedback and latency rules, per feature

The golden rule from v1 still stands: **the phone reacts instantly, the PC agrees a moment
later.** One table, so nobody has to guess:

| Feature | Phone behaviour | Network behaviour |
|---|---|---|
| Transport (play/pause/next/stop) | Instant state change + haptic | Fire immediately, one command |
| Seek / volume sliders | Optimistic, locked against incoming updates while dragging; the PC moves **while** the thumb does (user, 2026-09-22) | Live: throttled ≈8/s while dragging (≤ 20/s budget), final value on release |
| Fullscreen / mode / shuffle / repeat | Instant icon change | Fire immediately |
| EQ bands | Curve + slider move locally | Continuous; the PC coalesces at 120 ms |
| File list | Skeleton rows while loading; never a spinner over the whole screen | Paged, 200 rows, cached by path in RAM |
| Subtitle search / download | Progress row with the PC's reason on failure | One request, one result message, then a state push |
| Queue jump | Row highlights immediately, PC catches up | One command |
| Start over seat | Appears and disappears **with the PC's Resume toast** — never on a phone timer of its own, never optimistic: the tap sends `restart` and the seat goes when the PC's toast does | Nothing pushed for it beyond `playback.resume` in the snapshot (one int while the toast is up, `null` otherwise) |
| Playlist card | Auto-scrolls to the current row on every track change; >5 rows scroll inside the 5-row window (user, 2026-09-22) | Titles fetched in `queue_get` pages of 100 when `queue.count` changes; an index-only move is pure local scroll. Clear = confirm + one `queue_clear` |
| Web media controls (play/pause · −10 s/+10 s · seek · volume · mute · fullscreen) | Optimistic icon + slider state, like transport, plus an **optimistic hold**: a write parks its value until the PC's own reading agrees with it (or 1.5 s pass and the PC's word wins), so the 1/s poll can never drag the thumb back to where it was | Position read ~1/s (`web_media_get`), **one read in flight at a time**; the seek bar streams ≈4/s while dragging — a page player is being scrubbed, not nudged — and volume ≈8/s, both in the units the PC last spoke (`remote.md` §17.4) |
| Tabs · saved pages · bookmarks (Web mode) | The sheet opens at once with whatever it already knows; a spinner only for the list itself, and one honest line for a PC that has not been updated | One request per sheet (`web_tabs_get` · `library_get` · `web_bookmarks_get`), re-read after every change; the lists never ride the snapshot (`remote.md` §17.13.3) |

---

## 9. Marks to draw

The APK ships **no image assets** — every icon is a `CustomPainter`, ported from the PC's
`transport_marks.dart` / `salu_marks.dart` so both apps draw identical marks. New ones
needed for this scope (add them on the PC side first, then port):

`FolderMark` · `DriveMark` · `FileMediaMark` · `SubtitleMark (CC)` · `EqualizerMark` (exists) ·
`GlobeMark (web)` · `LinkMark` · `FullscreenMark` · `ChevronMark` · `SearchMark` ·
`ResetMark` · `QueueMark`

Same recipe: `markStrokeFor(size)` for the stroke, `markInk(context)` for the colour,
nothing filled, nothing boxed. At phone sizes the minimum stroke wants to be a touch
heavier (1.8–2.0) than at the PC's 18 px.

---

## 10. Build order (updated)

| Step | Deliverable | Notes |
|---|---|---|
| **A1** | Connect sheet → **Play** (transport, seek, volume) with the mode pill **and the playlist card** (5 rows, auto-scroll, tap-to-jump). | The proof. The card moved into A1 (user's answer #4) — `queue_get`/`queue_jump` are tiny reads the PC ships with R1. |
| **A2** | **Browse → Streams** (+ Add URL) and **Browse → Files** (read-only browser, pinned places, quick `▶`/`＋` marks). | Highest happiness per line of code in the whole app. |
| **A3** | **Tune → Subtitles** (tracks, sync, search, download) and **Tune → Audio**. | First feature that can genuinely save a ruined movie night. |
| **A4** | **Tune → Equalizer** + presets + Speed chips; **select mode** (checkboxes, select-all, bottom action bar) in Files. | EQ last, on purpose: it is the least-used tool in the set. |
| **A5** | Web mode body in both shapes (nav + web media + open-URL), Focus mode, Settings → Play screen, collapse memory, activity dot. | The polish pass that makes it feel like a finished product. |

Each step is usable on its own, and the app is never in a broken state between steps.

---

## 11. Deliberately not added (and the reason, so it is not re-litigated)

| Not in v1 | Why |
|---|---|
| Thumbnails / posters in the file browser | Sending images over the socket turns the fastest screen into the slowest. Names + sizes are enough to pick an episode. |
| Picture / Aspect lines of the PC's Tune panel | They change the *picture*, which you cannot judge from a phone. **Speed is no longer in this table** — it joined Tune → Equalizer as chips (§6.1, user's answer #5). |
| Subtitle **style** overrides (font, size, colour, position) | Every one of them is a "look at the screen and adjust" job. It belongs on the PC. |
| Clearing the EQ learning memory | Destructive, invisible, and irreversible from the phone. |
| Queue editing (remove / reorder) | The PC does it better with a mouse. Jumping is what the phone is for. |
| Downloads shelf in Web mode | A PC-side surface with nothing a couch user would do with it. **The tab list, tab close, tab switch, new tab and the bookmark mirror are no longer in this table** — the phone side is built and the PC side is specified (`remote.md` §17.13, work order `pc_part.md`). |
| Fetching a subtitle from a **URL** | SALU deliberately never loads remote subtitle streams (`cc.md` D6) — a new rule would be needed, so it is a v2 decision, not an accident. |
| A foreground service to control with the phone locked | v2; v1 keeps the screen awake while the app is open. |

---

## 12. The advice I would give you before you build any of this

1. **The app just doubled in size — protect the three tabs.** The moment a fourth tab
   appears, the everyday remote has been buried. Files, Streams, EQ, Subs and Audio all
   fit under three intent-based tabs; keep it that way and use the collapse rules for
   everything else.
2. **Build Browse → Files before the Equalizer.** People use "play the next episode" every
   single evening; they touch the EQ twice a year. Build in order of how often a thumb
   will touch it.
3. **Privacy posture changed — decide it consciously.** Until now the phone learned
   nothing about your PC. A file browser sends folder names and file names, on demand. It
   is still read-only, still authenticated, still LAN-only, and there is a PC-side switch
   to turn it off (`remote.md` §17.6) — but it *is* a change, so it gets its own toggle
   rather than hiding inside the remote switch.
4. **Never let the phone become a file manager.** No rename, no delete, no move, no
   upload. The day someone asks for those, the answer is "use the PC".
5. **Test the ugly states first:** PC asleep, wrong folder, subtitle quota hit, file moved.
   Those are the states that decide whether the app feels trustworthy — far more than how
   pretty the EQ sliders are.
6. **One keyboard rule:** anywhere the phone can type (URL, subtitle search, folder
   search), the field opens pre-filled with the PC's best guess and the clipboard is
   checked first. Typing on a phone next to a PC is the thing you are trying to abolish.
7. **Keep the visual language identical to SALU.** Same palette, same thin marks, same
   quiet surfaces. The APK should look like SALU's own remote, not a third-party tool that
   happens to connect to it.

---

## 13. Open questions — all answered (2026-09-20)

No open questions remain. The six answers, kept as a record so they are never re-litigated:

| # | Question | Your answer | What it became |
|---|---|---|---|
| 1 | File browsing default | "As you said, I agree" | **ON**, with the switch visible in both the APK's Files tab and the PC's Remote panel (`remote.md` §17.6). |
| 2 | Multi-select | Checkbox multi-select with select-all/deselect; per-item play/add — "+ and ▶ buttons" | **§5.1**: quick `▶`/`＋` marks on every row, long-press → checkbox mode, `N selected` header with **Select all ⇄ Deselect**, bottom bar `▶ Play N · ＋ Queue N · ✕`. |
| 3 | EQ in landscape | "What is best you select" | **Assistant: yes, EQ-only landscape** — mixing-desk layout (§6.1). |
| 4 | Queue card vs screen | "Does it mean playlist? If yes: collapsible, autoscroll, max 5" | Yes — it is the playlist. **Collapsible card, auto-scrolls to the now-playing row, 5 rows visible, tap a row to jump** (§4.1). Moved into A1; PC ships `queue_get`/`queue_jump` with R1. |
| 5 | Speed chips | "What is best you feel" | **Assistant: in** — chips at the bottom of Tune → Equalizer, the PC's own stops 0.5×–3× (§6.1). |
| 6 | Activity indicator | "Do what is best" | **Assistant: yes** — one quiet dot by the connection dot, 300 ms delay, no text (§4.1). |
| + | *(new rule you added)* | Web page playing media → **only basic controls**: play/pause, seek bar, volume, mute, fullscreen | **§4.2**, two shapes. PC side: `remote.md` §17.11 (JavaScript on the page's own player) — with the honest limit: cross-origin/DRM players hide the controls instead of failing. |
