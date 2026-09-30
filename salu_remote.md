# SALU Remote — one file

> **This file replaced five.** It was compiled on **2026-09-30** in `hamamun/salu-remote` from `README.md`, `SETUP_STEP_BY_STEP.md`, `remote.md`, `remote_apk_ui.md` and `pc_part.md`, all five of which have since been deleted from the repository. Nothing was rewritten or summarised away: each document became a Part below, its headings one level deeper, its section numbers untouched. Part 6 is new — an audit of this file against the code as it actually stands.

The repository itself is **the Android app** (`lib/`, `test/`, `android/`). The PC application it talks to lives in a different repository, `hamamun/Salu`, and is **not** in this checkout — so Parts 3 and 5 are the specification and work orders that the other side implements, kept here because the phone's own code comments cite them line by line.

## How the old file names map onto this one

Every Dart file in this repository carries doc comments in the shape `remote.md §17.4` or `remote_apk_ui.md §6.0`. Those names are now gone, so read them like this — **the section numbers are unchanged**:

| Cited in code as | Now lives in | Covers |
|---|---|---|
| `README.md` | **Part 1** | The repository at a glance, the current milestone, and every build/run symptom anyone has actually hit (Gradle vs Java, no Windows desktop project, firewall). |
| `SETUP_STEP_BY_STEP.md` | **Part 2** | Parts 0–8 for a person who is not a coder: create the skeleton, push it, paste the files, the three Android edits, pair with SALU, and the symptom table. |
| `remote.md` | **Part 3** | The wire protocol, the snapshot, every verb, every error code, the PC UI, the build order — and the v1.1 expansion (§17) that added files, streams, EQ, subtitles, web mode, tabs, the trackpad and PC power. |
| `remote_apk_ui.md` | **Part 4** | The phone's three tabs, the space system, every screen, the mouse pad, the feedback/latency rules, the marks to draw, and what the phone cannot know and must be told. |
| `pc_part.md` | **Part 5** | The shopping lists for the other repository: F (large playlists + grouping), E (connection reliability), D (PC power), C (the web fixes), A (the web section), B (the `fs_places` drive scan and channel grouping). |

One exception worth knowing: `pc_part.md §11` in a code comment means **Part 5 → Part B → §11** (channel grouping), because Part B numbers its own sections 1–12 rather than using the `B1` style of the other work orders.

## Status at a glance (2026-09-30)

| Area | Phone (this repo) | PC (`hamamun/Salu`) |
|---|---|---|
| Pairing (QR + `salu://pair`), transport, volume, queue card | built | built |
| Browse (Files · Streams), Tune (EQ · Subs · Audio) | built | built |
| Web mode: page player, tabs, saved pages, Home, one fullscreen seat, trackpad | built, feature-flagged | Part A + Part C — **acceptance on the user's PC pending** |
| Sleep PC / Shut down PC in ⋮ | built, gated on `pc_power` | Part D — **acceptance pending** |
| Connection reliability (heartbeat, stall nudge, replay) | built, **revised 2026-09-30 — Part 7** | Part E applied; Part G — **not yet started** |
| Large playlists + capability-gated grouping | built, gated on `queue_groups_paged` | Part F — **implementation pending** |

## Contents

- **Part 1** — This repository — what it is, how to build it, what breaks *(was `README.md`)*
- **Part 2** — Setup, step by step (no coding needed) *(was `SETUP_STEP_BY_STEP.md`)*
- **Part 3** — PC-side protocol and implementation specification (§1 – §17.15) *(was `remote.md`)*
- **Part 4** — APK interface design (§1 – §13) *(was `remote_apk_ui.md`)*
- **Part 5** — PC work orders for `hamamun/Salu` (Parts A – F) *(was `pc_part.md`)*
- **Part 6** — Audit: this file against the code (2026-09-30)
- **Part 7** — Connection reliability, round two: the busy PC (2026-09-30) *(hand-written — see its note)*

### Contents of Part 1 — This repository — what it is, how to build it, what breaks

  - [Current milestone](#current-milestone)
  - [Run from Android Studio](#run-from-android-studio)
  - [Troubleshooting](#troubleshooting)

### Contents of Part 2 — Setup, step by step (no coding needed)

  - [Part 0 · What we are making, in one paragraph](#part-0--what-we-are-making-in-one-paragraph)
  - [Part 1 · Create the app skeleton and prove it runs (30 min)](#part-1--create-the-app-skeleton-and-prove-it-runs-30-min)
  - [Part 2 · Create your Git repository and put the skeleton in it](#part-2--create-your-git-repository-and-put-the-skeleton-in-it)
  - [Part 3 · Paste my files into the repository (20 min)](#part-3--paste-my-files-into-the-repository-20-min)
  - [Part 4 · The three Android edits (10 min)](#part-4--the-three-android-edits-10-min)
  - [Part 5 · Run it and pair with SALU](#part-5--run-it-and-pair-with-salu)
  - [Part 6 · If something goes wrong](#part-6--if-something-goes-wrong)
  - [Part 7 · What to send me when it breaks](#part-7--what-to-send-me-when-it-breaks)
  - [Part 8 · What comes next (so you know where this is going)](#part-8--what-comes-next-so-you-know-where-this-is-going)

### Contents of Part 3 — PC-side protocol and implementation specification (§1 – §17.15)

  - [1. The locked decisions](#1-the-locked-decisions)
  - [2. Non-goals for this phase](#2-non-goals-for-this-phase)
  - [3. Why this is small work in this codebase](#3-why-this-is-small-work-in-this-codebase)
  - [4. Architecture](#4-architecture)
  - [5. File map](#5-file-map)
  - [6. The protocol (v1)](#6-the-protocol-v1)
  - [7. Server behaviour, in detail](#7-server-behaviour-in-detail)
  - [8. Networking details that decide "it just works"](#8-networking-details-that-decide-it-just-works)
  - [9. Command table (v1)](#9-command-table-v1)
  - [10. PC-side UI](#10-pc-side-ui)
  - [11. Lifecycle and persistence](#11-lifecycle-and-persistence)
  - [12. Auto-discovery (P3 — the bonus, build only after R4)](#12-auto-discovery-p3--the-bonus-build-only-after-r4)
  - [13. Build order and acceptance criteria](#13-build-order-and-acceptance-criteria)
  - [14. Test plan](#14-test-plan)
  - [15. Troubleshooting table (put this in the release notes)](#15-troubleshooting-table-put-this-in-the-release-notes)
  - [16. Open questions (deliberately left open)](#16-open-questions-deliberately-left-open)
  - [17. Expanded scope — v1.1 (added 2026-09-20)](#17-expanded-scope--v11-added-2026-09-20)
  - [17.15 PC power from the phone's three-dot menu (2026-09-24)](#1715-pc-power-from-the-phones-three-dot-menu-2026-09-24)

### Contents of Part 4 — APK interface design (§1 – §13)

  - [1. What changed, and the one sentence that still decides everything](#1-what-changed-and-the-one-sentence-that-still-decides-everything)
  - [2. The new shape: three tabs, by intent](#2-the-new-shape-three-tabs-by-intent)
  - [3. The space system — how showing/hiding actually works](#3-the-space-system--how-showinghiding-actually-works)
  - [4. Tab 1 — Play](#4-tab-1--play)
  - [5. Tab 2 — Browse](#5-tab-2--browse)
  - [6. Tab 3 — Tune](#6-tab-3--tune)
  - [7. What the phone cannot know — and must be told](#7-what-the-phone-cannot-know--and-must-be-told)
  - [8. Feedback and latency rules, per feature](#8-feedback-and-latency-rules-per-feature)
  - [9. Marks to draw](#9-marks-to-draw)
  - [10. Build order (updated)](#10-build-order-updated)
  - [11. Deliberately not added (and the reason, so it is not re-litigated)](#11-deliberately-not-added-and-the-reason-so-it-is-not-re-litigated)
  - [12. The advice I would give you before you build any of this](#12-the-advice-i-would-give-you-before-you-build-any-of-this)
  - [13. Open questions — all answered (2026-09-20)](#13-open-questions--all-answered-2026-09-20)

### Contents of Part 5 — PC work orders for `hamamun/Salu` (Parts A – F)

- [Part F — large playlists, grouping parity and Web-mode stability (2026-09-26)](#part-f--large-playlists-grouping-parity-and-web-mode-stability-2026-09-26)
  - [F0. What the Remote now does / rollout](#f0-what-the-remote-now-does--rollout)
  - [F1. PC playlist panel must observe shared grouping state](#f1-pc-playlist-panel-must-observe-shared-grouping-state)
  - [F2. Exact, byte-bounded grouping protocol — REQUIRED wire contract](#f2-exact-byte-bounded-grouping-protocol--required-wire-contract)
  - [F3. Avoid repeated heavy work on the PC](#f3-avoid-repeated-heavy-work-on-the-pc)
  - [F4. Web-mode polling and disconnect diagnosis](#f4-web-mode-polling-and-disconnect-diagnosis)
  - [F5. Acceptance / regression checklist](#f5-acceptance--regression-checklist)
- [PC part — work orders for the Salu repo](#pc-part--work-orders-for-the-salu-repo)
- [Part E — connection reliability: keep the phone linked (2026-09-26)](#part-e--connection-reliability-keep-the-phone-linked-2026-09-26)
  - [E0. What the phone already changed (context — no PC work)](#e0-what-the-phone-already-changed-context--no-pc-work)
  - [E1. Answer `ping` on the socket path — `lib/core/remote/remote_service.dart`](#e1-answer-ping-on-the-socket-path--libcoreremoteremoteservicedart)
  - [E2. Socket I/O stays on the main isolate — `remote_service.dart` / architecture check](#e2-socket-io-stays-on-the-main-isolate--remoteservicedart--architecture-check)
  - [E3. `state_get` stays prompt under load — `remote_command_handler.dart`](#e3-stateget-stays-prompt-under-load--remotecommandhandlerdart)
  - [E4. Connection bookkeeping — `remote_service.dart`](#e4-connection-bookkeeping--remoteservicedart)
  - [E5. Fresh-socket snapshot and `rev` — verify only](#e5-fresh-socket-snapshot-and-rev--verify-only)
  - [E6. Spec rows to fix in `remote.md` (same sitting as the code)](#e6-spec-rows-to-fix-in-remotemd-same-sitting-as-the-code)
  - [E7. Tests to add on the PC side](#e7-tests-to-add-on-the-pc-side)
  - [E8. Acceptance checklist (verify on the user's PC, in this order)](#e8-acceptance-checklist-verify-on-the-users-pc-in-this-order)
- [Part D — sleep and shut down from the remote's ⋮ menu (2026-09-24)](#part-d--sleep-and-shut-down-from-the-remotes--menu-2026-09-24)
- [Part C — the web fixes the user reported after using it (2026-09-24)](#part-c--the-web-fixes-the-user-reported-after-using-it-2026-09-24)
  - [C0. What the user reported, in their words](#c0-what-the-user-reported-in-their-words)
  - [C1. One fullscreen seat that actually works — `web_fullscreen`](#c1-one-fullscreen-seat-that-actually-works--webfullscreen)
  - [C2. Home — `browser_nav {action:"home"}`](#c2-home--browsernav-actionhome)
  - [C3. The trackpad — `web_mouse_move` / `web_mouse_click`](#c3-the-trackpad--webmousemove--webmouseclick)
  - [C4. Add-only bookmarks — `web_bookmark_add`](#c4-add-only-bookmarks--webbookmarkadd)
  - [C5. The blank new tab — `web_tab_new {url}`](#c5-the-blank-new-tab--webtabnew-url)
  - [C6. Housekeeping, tests, and the phone-side file list](#c6-housekeeping-tests-and-the-phone-side-file-list)
  - [Part C — implementation record (2026-09-24)](#part-c--implementation-record-2026-09-24)
- [Part A — the web section (2026-09-23)](#part-a--the-web-section-2026-09-23)
  - [A0. What the user reported, and what it means](#a0-what-the-user-reported-and-what-it-means)
  - [A1. Make the units explicit — `remote_web_media_bridge.dart`](#a1-make-the-units-explicit--remotewebmediabridgedart)
  - [A2. Find the page's real player, not its advert](#a2-find-the-pages-real-player-not-its-advert)
  - [A3. `web_key` and `web_focus_get` — the D-pad (phone side: built)](#a3-webkey-and-webfocusget--the-d-pad-phone-side-built)
  - [A4. The tab strip mirror — list, switch, close, new (phone side: built)](#a4-the-tab-strip-mirror--list-switch-close-new-phone-side-built)
  - [A5. The bookmark mirror — read-only (phone side: built)](#a5-the-bookmark-mirror--read-only-phone-side-built)
  - [A6. Housekeeping that must not be skipped](#a6-housekeeping-that-must-not-be-skipped)
  - [A7. Tests to add on the PC side](#a7-tests-to-add-on-the-pc-side)
  - [A8. Acceptance checklist (verify on the user's PC, in this order)](#a8-acceptance-checklist-verify-on-the-users-pc-in-this-order)
  - [A9. Order of work](#a9-order-of-work)
  - [A10. Before shipping the phone side (one honest caveat)](#a10-before-shipping-the-phone-side-one-honest-caveat)
  - [Part A — implementation record (2026-09-24)](#part-a--implementation-record-2026-09-24)
- [Part B — the `fs_places` drive scan, the group-by pill and channel grouping (2026-09-22)](#part-b--the-fsplaces-drive-scan-the-group-by-pill-and-channel-grouping-2026-09-22)
  - [1. The bug (confirmed from the code, 2026-09-22)](#1-the-bug-confirmed-from-the-code-2026-09-22)
  - [2. The rule that fixes it (non-negotiable)](#2-the-rule-that-fixes-it-non-negotiable)
  - [3. Changes in `lib/core/remote/remote_fs_service.dart`](#3-changes-in-libcoreremoteremotefsservicedart)
  - [4. Changes in `lib/core/remote/remote_command_handler.dart`](#4-changes-in-libcoreremoteremotecommandhandlerdart)
  - [5. Linux/macOS builds](#5-linuxmacos-builds)
  - [6. Tests — extend `test/remote_fs_test.dart`](#6-tests--extend-testremotefstestdart)
  - [7. Docs to mirror (if present in this repo)](#7-docs-to-mirror-if-present-in-this-repo)
  - [8. Out of scope — do not change](#8-out-of-scope--do-not-change)
  - [9. Acceptance checklist (verify on the user's PC shape)](#9-acceptance-checklist-verify-on-the-users-pc-shape)
  - [10. Group-by pill does not open while a phone is connected (investigate and fix)](#10-group-by-pill-does-not-open-while-a-phone-is-connected-investigate-and-fix)
  - [11. Channel grouping on the phone (new protocol + PC duties)](#11-channel-grouping-on-the-phone-new-protocol--pc-duties)
  - [12. Phone-local channel favourites + queue search (no PC work needed, future sync optional)](#12-phone-local-channel-favourites--queue-search-no-pc-work-needed-future-sync-optional)

### Contents of Part 6 — Audit

- [Part 6 · Audit: this file against the code (2026-09-30)](#part-6--audit-this-file-against-the-code-2026-09-30)
- [6.1 What the inherited Parts 1–5 did not cover](#61-what-the-inherited-parts-15-did-not-cover)
- [6.2 The phone's complete error vocabulary](#62-the-phones-complete-error-vocabulary)
- [6.3 The Android surface as it actually is](#63-the-android-surface-as-it-actually-is)
- [6.4 The file map — every Dart file in this repository](#64-the-file-map--every-dart-file-in-this-repository)
- [6.5 What this audit could not check](#65-what-this-audit-could-not-check)

---

# Part 1 · This repository — what it is, how to build it, what breaks

> *(This Part was the whole of `README.md`; its headings are one level deeper than they used to be, its section numbers are unchanged.)*

SALU Remote is the Android companion app for SALU. The phone connects to SALU on the
same local Wi-Fi and sends playback commands; SALU remains responsible for playback and
for the media itself.

### Current milestone

The current build contains the full v2 scope:

- **Pairing two ways** — in-app QR scan (camera, via `mobile_scanner`) and the
  `salu://pair` deep link, both landing in the connect sheet with the PC pre-filled;
- **the three-tab interface** (Play · Browse · Tune):
  - **Play** — one icon-only transport row (play/pause · stop · previous ·
    next · −10 s · +10 s · fullscreen), a repeat · shuffle icon row,
    realtime seek/volume sliders (they fire while dragging), mute + volume,
    the now-playing/queue card (tap a row to jump, ✕ clears the playlist),
    the mode pill, and — in web mode — the **web body**: a nav row
    (home · back · forward · reload · one fullscreen seat the PC decides the
    target of), the page doors (**＋ New tab** · **☆ Saved pages** — the PC
    browser's bookmarks, and nothing else), the **Open tabs** section at the
    foot (collapsible, remembered, exactly the queue card's shape), and the page
    player's own controls (live seek bar, −10 s / +10 s, the big play/pause,
    live volume + mute). Long-press the page card for **Web diagnostics** — what
    the PC reported, in its own numbers;
  - **Browse** — Files (PC's own file tree, read-only) and Streams (saved
    streams with the PC's health verdict), greyed out while the PC is in web
    mode;
  - **Tune** — Equalizer (the PC's presets and curve, drag a band, speed
    chips), Subtitles (tracks, delay, search, file picker, auto-download) and
    Audio tracks; in web mode the tab becomes a **mouse pad** — one trackpad
    box and one line under it. Drag moves SALU's own cursor, a tap is a left
    click, a double tap is Enter;
- **focus mode** — Play with only the essential controls, one gesture away;
- **Sleep PC** and **Shut down PC** in the three-dot menu (both require confirmation,
  remain disabled while offline or until SALU on the PC advertises `pc_power`);
- the **connect sheet** (QR / manual / paste, diagnostics, remember me),
  **settings** (phone name + the show/hide checklist), reconnect to a
  remembered PC, live playback state and connection feedback from the PC.

The Android permissions, API level, screen-awake channel and persistence dependency are
already applied in this checkout. `flutter pub get` before the first run — the QR scanner
added one dependency (`mobile_scanner`).

**Waiting on the PC (2026-09-24).** The web section is complete on this side: live seek and
volume bars with an optimistic hold, −10 s / +10 s, the Home seat, one fullscreen seat, the
**Open tabs** section (list · switch · close · new), Saved pages (the PC browser's bookmarks,
with add-only saving), Web diagnostics and the mouse pad. Everything that needs new plumbing
on the PC is **feature-flagged**, so it lights up the moment SALU advertises
`web_media_unit`, `web_tabs`, `web_bookmarks`, `web_key`, `web_home`, `web_fullscreen`,
`web_mouse` and `web_bookmark_add` — and until then each door degrades into something useful
rather than something dead. [`pc_part.md`](#part-5--pc-work-orders-for-hamamunsalu-parts-a--f) is the work order for that side
(Part C); `remote.md` §17.13 and §17.14 are the protocol it implements.

**Power actions also need a PC update.** This repository is the Android client only.
The menu and wire commands are ready, but Sleep PC / Shut down PC stay disabled until
SALU for Windows implements `pc_sleep` / `pc_shutdown` and advertises `pc_power`.
The PC-side work order is [`pc_part.md` Part D](#part-5--pc-work-orders-for-hamamunsalu-parts-a--f), with its protocol in
[`remote.md` §17.15](#part-3--pc-side-protocol-and-implementation-specification-1--1715).

### Run from Android Studio

Gradle in this checkout is pinned to the **Flutter 3.47 template set** — Gradle `9.3.1` + AGP `9.1.0`
+ Kotlin `2.4.0`, which runs on Java **17–25**. If your Java is 26+ (or you are on an old checkout
still on Gradle 8.10.2), see
[Troubleshooting § Java/Gradle incompatibility](#build-fails-gradle-build-failed-due-to-javagradle-incompatibility-java-2503).

1. Open this repository as a Flutter project.
2. Connect an Android phone with USB debugging enabled.
3. From the repository root run `flutter pub get` once.
4. Select the phone and press **Run**.
5. Follow [`SETUP_STEP_BY_STEP.md`](#part-2--setup-step-by-step-no-coding-needed) to pair it with SALU.

`remote.md` is the PC-side protocol/implementation specification. `remote_apk_ui.md` is
the Android interface specification. They are design and implementation references, not
additional setup commands.

### Troubleshooting

#### Error: `No Windows desktop project configured` when pressing Run

This project is **Android-only** (only the `android/` folder exists). That error means
Android Studio's device dropdown is set to **Windows (windows-x64)** instead of your phone.

**Fix — select your Android phone:**

1. Look at the top toolbar in Android Studio, center — there is a device selector dropdown. If it says `Windows` or `Chrome` or `Edge`, that's the problem.
2. Plug your phone in via USB. On the phone: enable **Developer options** → **USB debugging**, set USB mode to **File Transfer (MTP)**, and accept the **Allow USB debugging?** prompt (tick *Always allow*).
3. In Android Studio, click the device dropdown → you should now see your phone model (e.g. `sdk gphone` or `SM-A...` or `Redmi...`). Select it.
4. Press **Run** again.

**Verify from terminal:**

```bash
flutter devices
# You should see at least one android device, e.g.:
# sdk gphone ... • android-arm64 • Android 14

flutter pub get
flutter run -d <your-device-id>   # e.g. flutter run -d  emulator-5554  or  -d  192.168...
```

If `flutter devices` shows no Android device:

- Run `adb devices` — if empty, unplug/replug cable, try another USB port/cable, and re-allow debugging on phone.
- On Windows: `File > Settings > Appearance & Behavior > System Settings > Android SDK > SDK Tools` → check **Google USB Driver** → Apply.
- On Xiaomi/Redmi/POCO: also enable **Install via USB** and **USB debugging (Security settings)** in Developer options.

**If you actually want Windows support** (not needed for SALU Remote):

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows .
```

Then `windows/` folder will be generated and `flutter run -d windows` will work. For the SALU Remote phone app you don't need this — keep it Android-only.

#### Warnings: `A restricted method in java.lang.System has been called` during Gradle build

You will see this when running on your phone:

```
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning
```

**This is NOT an error — it's a harmless warning from Gradle 9 running on Java 24/25** (the JDK started restricting `System::load` from unnamed modules). Your app is still building. The first `assembleDebug` can take **5-15 minutes** downloading dependencies.

> **But check the tail of the log.** The warning is only harmless if the build *continues*. If the
> same log ends with `FAILURE: Build failed with an exception` / `Error: Gradle build failed due to
> Java/Gradle incompatibility`, the JDK and Gradle really do disagree — see the next section.

Just **wait**. After the warnings you should see:

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...
```

If the build hangs for >20 min or ends with a real error (red text `FAILURE` or `Exception`), copy the last 50 lines and send them.

**Why you get it and why we keep it:** the warning can also be silenced by staying on Gradle 8.10.2
+ AGP 8.7.3 + Kotlin 2.1.0 — that is what this repo used to do, and it broke every machine on Java 24+
(see below), while Flutter 3.41+ now *errors* on those three versions anyway. The repo is back on the
Flutter template numbers; this warning is the cheap half of that trade. **Ignore it and wait** — the
first `assembleDebug` after a Gradle bump is slow.

#### Build fails: `Gradle build failed due to Java/Gradle incompatibility` (Java 25.0.3)

> **Already fixed in this checkout:** the build is on the Flutter 3.47 template set — Gradle `9.3.1`,
> AGP `9.1.0`, Kotlin `2.4.0` — which runs on Java **17–25**. Pull and rebuild with
> [the repo-side fix](#the-repo-side-fix-already-applied). Read on for why, and use the
> [fallback](#fallback--keep-an-old-gradle-but-give-it-an-older-jdk) only for a checkout you are not
> allowed to touch.

Same log as the warning above, but the build stops. The giveaway is a `What went wrong:` block that
contains nothing but a Java version number:

```
FAILURE: Build failed with an exception.

* What went wrong:
25.0.3

* Try:
> Run with --stacktrace option to be more verbose.

BUILD FAILED in 50s
Error: Gradle build failed due to Java/Gradle incompatibility.
The Java version used for the build is 25.0.3, which is incompatible with Gradle 8.10.2.
```

**What it means:** the JDK that Flutter hands to Gradle is newer than the Gradle the project pins can
run on. Gradle prints the Java version as the entire error message — that is where the lone `25.0.3`
line comes from.

| Java version running Gradle | Oldest Gradle that supports it |
|---|---|
| 17 | 7.3 |
| 21 | 8.5 |
| 23 | 8.10 |
| 24 | 8.14 |
| 25 | 9.1.0 |
| 26 | 9.4.0 |

Source: [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html#java).
This is about the JVM that *runs Gradle*, **not** about `compileOptions` / `jvmTarget = 17` in
`android/app/build.gradle.kts` — leave those at 17, they are your app's bytecode level.

Downgrading Gradle is not a durable escape hatch either — Flutter's own `DependencyVersionChecker`
picks its own fights. On **Flutter 3.47** it *errors* below Gradle `8.14.0`, AGP `8.11.1`, Kotlin
`2.2.20` and *warns* below `9.1.0` / `9.0.1` / `2.3.20` (Flutter 3.44 was one notch more lenient:
error floors `8.7.0` / `8.6.0` / `2.0.0`), while `gradle_utils.dart` caps what it knows at Gradle
`9.3.1`, AGP `9.2`, KGP `2.4.0`. The set this repo now pins — `9.3.1` / `9.1.0` / `2.4.0` — is exactly
the Flutter 3.47 template default, i.e. above every floor and inside every ceiling.

One more thing in that log that is not yours: `I/flutter … NtLifecycle->scheduledWakeUp tag:KeepAlive,
length:Instance of 'BluetoothHelper',Instance of 'NtWatchWorker'` is **not from SALU Remote** — nothing
in `lib/` logs those tags. It is logcat noise from another app on the phone, printed while Gradle was
working.

##### The repo-side fix (already applied)

Three pins move together and nothing else does:

| File | Was | Now |
|---|---|---|
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle `8.10.2-all` | Gradle `9.3.1-all` |
| `android/settings.gradle.kts` | AGP `8.7.3` | AGP `9.1.0` |
| `android/settings.gradle.kts` | Kotlin `2.1.0` | Kotlin `2.4.0` |

`9.3.1` is not arbitrary: AGP `9.1.x` requires Gradle ≥ `9.3.1`, Gradle ≥ `9.1.0` is what makes Java 25
runnable, `9.3.1` is Flutter 3.47's newest known-good, and Gradle `9.6+` drops internal APIs AGP 8.x
still used (irrelevant now, but it is why "just take the latest" was not chosen). No app code, manifest,
`compileSdk` or `minSdk` change. `android.newDsl=false` and `android.builtInKotlin=false` in
`android/gradle.properties` stay as they are — Flutter's own template ships those with AGP 9 so the
legacy `android { }` / `kotlin { compilerOptions { jvmTarget } }` blocks keep working.

Rebuild after pulling, from the repository root:

```powershell
git pull
flutter clean
cd android
.\gradlew.bat --stop      # kill daemons still holding Gradle 8.10.2
cd ..
flutter pub get
flutter run -d ZPFU9LU8AEFISWPV
```

Then in Android Studio: **File → Sync Project with Gradle Files** — or *Invalidate Caches… → Restart* if
the editor still shows stale errors — and press **Run ▶**.

What to expect on that first run:

- Gradle downloads `9.3.1` (a few hundred MB) plus new AGP/Kotlin artifacts: **3–10 minutes**.
- The `WARNING: A restricted method in java.lang.System has been called` lines come back. Harmless —
  that is Gradle 9 on Java 24/25, and silencing it by downgrading is what broke the build.
- Success is `✓ Built build\app\outputs\flutter-apk\app-debug.apk` followed by `Installing…`.
- The old `gradle-8.10.2-all` folder under `%USERPROFILE%\.gradle\wrapper\dists\` is dead weight;
  `rmdir /s /q` it whenever you like.

If you instead get *"Failed to install the following Android SDK components"* or a complaint about
*platform android-36* / *NDK 28.2*: Android Studio → **Settings → Languages & Frameworks → Android SDK**
→ install **Android 16 (API 36)** (tick *Show Package Details* for the NDK), accept the licences:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --licenses
```

(use the SDK folder `flutter doctor --verbose` prints under *Android SDK at*) and run the build again.

Optional, once, so the wrapper files themselves match the distribution (the 8.10.2 `gradle-wrapper.jar`
works fine, this only keeps Android Studio from nagging):

```powershell
cd android
.\gradlew.bat wrapper --gradle-version 9.3.1 --distribution-type all
cd ..
git diff --stat android/gradle android/gradlew   # then commit if it changed
```

To have Flutter audit a project's build versions instead of guessing (useful for other repos, and it
is the same checker these pins came from):

```bash
flutter analyze --suggestions
```

##### Fallback — keep an old Gradle but give it an older JDK

1. Find out which Java Flutter uses for Gradle:

   ```bash
   flutter doctor --verbose
   ```

   Under **Android toolchain** read `Java binary at:` and `Java version`. Flutter looks for a JDK in
   this order: `jdk-folder` set by `flutter config` → **the JDK bundled with your newest Android
   Studio** → `JAVA_HOME` → `java` on `PATH`. Because the Studio-bundled JDK beats `JAVA_HOME`,
   changing `JAVA_HOME` alone often looks like it did nothing — which is why the fix is `flutter config`.
   Java 25 there means either that bundled JBR *is* 25, or `JAVA_HOME` points at a JDK 25 you installed.

2. Find a JDK whose version is 17–23 and note its folder:

   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\java" -version    # newest Studio
   & "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java" -version  # per-user Studio install
   dir "C:\Program Files\Eclipse Adoptium","C:\Program Files\Java" -ErrorAction SilentlyContinue
   ```

   If every candidate is too new, install one side by side and leave `JAVA_HOME` / `PATH` untouched:
   [Temurin 21 LTS MSI](https://adoptium.net/temurin/releases/?version=21). It must be a JDK, not a JRE
   (`bin\javac.exe` has to exist).

3. Tell Flutter to use it — one line covers the terminal *and* Android Studio's Run button, because
   Studio only runs the same `flutter … run` command:

   ```powershell
   flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.0.5.11-hotspot"
   ```

   Prefer a JDK you installed over Studio's `jbr` where you can: Studio updates replace the bundled
   JBR, so it moves to Java 26/27 whether you like it or not. To undo it, set the value to an empty
   string (`flutter config --jdk-dir ""`) — `flutter config` has no per-setting "clear" flag.

4. Same JDK in Studio, otherwise the Gradle tool window keeps showing red while the app builds fine:
   **File → Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK** → pick
   `jbr-17` / `jbr-21` / *Specified JDK…* → **Apply**. Skip if you only ever press Run ▶.

5. Clear daemons and rebuild: `flutter clean`, `.\gradlew.bat --stop` in `android/`, `flutter pub get`,
   `flutter run`. `flutter doctor --verbose` should then report a Java the pinned Gradle supports.

Machine-wide version of the same idea, for people who build from several terminals/IDEs: put it in
your **user** Gradle properties — `%USERPROFILE%\.gradle\gradle.properties` (create if missing):

```properties
# forward slashes; the ":" after the drive letter must stay escaped
org.gradle.java.home=C\:/Program Files/Eclipse Adoptium/jdk-21.0.5.11-hotspot
```

**Never** add that line to `android/gradle.properties`: that file is committed, and a
`C:\Users\mamun\…` path in it breaks the build on every other machine.

---

# Part 2 · Setup, step by step (no coding needed)

> *(This Part was the whole of `SETUP_STEP_BY_STEP.md`; its headings are one level deeper than they used to be, its section numbers are unchanged.)*

You will not write any code. You will **copy and paste** files, change **three lines** in
three files Android Studio created for you, and press **Run**.

Total time for Part 1–4: about 30–45 minutes the first time. Part 5 is 2 minutes.

Print this, or keep it open in the other monitor. Do not skip steps — every step is
verifiable before you move on.

---

### Part 0 · What we are making, in one paragraph

The SALU Remote app is a **separate app** (in your own Git repository) that lives on your
phone. It talks to SALU on your PC over your home Wi-Fi. The PC does all the thinking; the
phone is only a remote control. Right now the app knows how to **connect** and send
**play/pause, next, volume, mute** and so on — the SALU-looking interface, the QR scanner
and the other screens come next. You will be able to run it on your phone from Android
Studio after Part 4, and it will already control SALU after Part 5.

---

### Part 1 · Create the app skeleton and prove it runs (30 min)

#### 1.1 Check your tools

Open **Android Studio** → `File` → `Settings` → `Plugins` → make sure **Flutter** and
**Dart** are installed and enabled (restart if it asks).

Then open a terminal: on Windows press `Win`, type `powershell`, press Enter. Type this and
press Enter:

```bash
flutter doctor
```

You want to see green ticks next to **Flutter** and **Android toolchain**. Red text about
`cmdline-tools` or licences → run `flutter doctor --android-licenses` and accept with `y`.

There is **no need** to be a coder for any of this. If a command prints an error, stop and
send me the text.

#### 1.2 Create the app folder on your computer

In the same terminal, go to where you keep projects. For example:

```bash
cd $HOME/Documents
flutter create --org app.salu --project-name salu_remote --platforms=android salu-remote
```

> **One line, and it matters.** Type it exactly. It creates a folder called `salu-remote`
> containing a working (empty) app called `salu_remote`.

If it prints `All done!`, you are good.

#### 1.3 Run it on your phone (this proves everything works)

1. On your phone: `Settings` → `About phone` → tap **Build number** 7 times.
2. Go back → `System` → **Developer options** → turn on **USB debugging**
   (on Xiaomi/Redmi also turn on **Install via USB**).
3. Plug the phone into the PC with the cable. On the phone's notification, choose
   **File transfer (MTP)**, and accept the **"Allow USB debugging?"** pop-up
   (tick *Always allow from this computer*).
4. In the terminal, inside the app folder:

```bash
cd salu-remote
flutter run
```

Wait. The first run takes a few minutes. It ends with `Flutter run key commands` and the
phone shows the **Flutter counter app** (a screen with a number and a + button).

**STOP HERE. This is the milestone.** If the counter app is on your phone, your tools and
your phone are perfect, and anything that breaks later is my code — not your setup.

Press `q` in the terminal to quit the app.

---

### Part 2 · Create your Git repository and put the skeleton in it

#### 2.1 Make the repository

1. In a browser, go to **github.com** and log in.
2. Top-right `+` → **New repository**.
3. Name: `salu-remote`. Visibility: **Private** (or Public — your choice).
4. **Do not** tick "Add a README file". Press **Create repository**.
5. Leave the page open — you will upload into it.

#### 2.2 Upload the skeleton — the easy way

On the new repository page you will see **"uploading an existing file"** (in the
*Quick setup* box). Click it.

1. Open the `salu-remote` folder on your computer (`$HOME/Documents/salu-remote`).
2. In Windows Explorer: `View` → `Show` → **Hidden items** (so you can see `.gitignore`).
3. Drag these into the browser, **not** the folder itself — only its contents:

   `.gitignore` · `.metadata` · `analysis_options.yaml` · `android` · `lib` · `test` ·
   `pubspec.yaml` · `pubspec.lock` · `README.md` · `web` *(skip any of these that do not exist)*

4. **Do not** drag `build` or `.dart_tool` — they are large junk folders.
5. At the bottom: keep **Commit directly to the `main` branch** selected → **Commit changes**.

> **Drag-and-drop hiding folders?** Use the fallback: on the repository page press
> `Add file` → `Upload files`, click **choose your files**, and in the file picker select
> everything **inside** the folder (`Ctrl+A`) — including hidden ones (the picker shows
> them when you type `*` in the file-name box, or enable hidden files in the picker's
> View menu).

**Check:** the repository page now lists `android`, `lib`, `pubspec.yaml`, and
`lib/main.dart` exists when you click `lib`.

---

### Part 3 · Paste my files into the repository (20 min)

For each file below, on the repository page:

1. Press **`Add file`** → **`Create new file`**.
2. In the **name box at the top**, type the full path **exactly** as written in the table
   (slashes make folders — GitHub does that for you).
3. Paste the whole file contents.
4. Press **`Commit changes…`** → **`Commit changes`**.

Get the contents from the file list on the left of this screen (click the file, select all,
copy). Paste it exactly — do not retype, do not "tidy" it.

| # | Type this in the name box | What it is |
|---|---|---|
| 1 | `lib/protocol/remote_protocol.dart` | The shared wire rules, copied from SALU |
| 2 | `lib/core/reply.dart` | One reply type for every command |
| 3 | `lib/core/models.dart` | Turns the PC's messages into usable values |
| 4 | `lib/core/prefs.dart` | Remembers your PC forever |
| 5 | `lib/core/error_copy.dart` | The PC's errors in plain words |
| 6 | `lib/core/screen.dart` | Keeps the phone screen awake |
| 7 | `lib/core/client.dart` | The connection, reconnection and all commands |
| 8 | `lib/ui/theme.dart` | SALU's colours and look |
| 9 | `lib/main.dart` | **The screen** — replace the file that is already there |

> **For #9, `lib/main.dart` already exists.** When you type that name GitHub will say the
> file exists — click the **"Edit file" / "Delete and recreate"** option and paste mine over
> it. This is normal and correct.

**Check:** your repository now has `lib/core/` (6 files), `lib/protocol/` (1), `lib/ui/` (1)
and `lib/main.dart`.

---

### Part 4 · The three Android edits (10 min)

**Repository status:** these Android edits have already been applied to the current
`salu-remote` checkout. If you cloned or pulled this repository after that change, do not
paste the examples below over them again. Instead, verify that the files contain the
permissions, `minSdk = 24`, and `keepAwake` channel shown below, then continue to Part 5.

> **⚠ Correction added 2026-09-30, when this file was merged into `salu_remote.md`.** The `AndroidManifest.xml` and `MainActivity.kt` samples in **§4.1 and §4.3 of this Part** are the versions written on 2026-09-20, and the app has since grown two things they do not have: the **`ACCESS_NETWORK_STATE`** permission (needed by `connectivity_plus`, which is what makes *"network-up events redial at once"* work — Part 5 E0.3) and the second method channel **`app.salu.remote/deep_link`** (a QR scanned by the *camera app* rather than in-app arrives as an intent, so a cold start must be able to ask for it). Pasting either sample over the files in this checkout would break QR-from-camera and Wi-Fi-return reconnect. **The files as they actually are, read from disk, are in [§6.3](#63-the-android-surface-as-it-actually-is) — verify against those.**


The examples remain here as a reference in case your local checkout is older. Do these
**on your computer**, in Android Studio — it underlines mistakes as you type, which the
web page cannot.

Open Android Studio → `File` → `Open…` → choose your `salu-remote` folder.

#### 4.1 Give the app the internet and camera

1. In the left panel open: `android` → `app` → `src` → `main` → **`AndroidManifest.xml`**.
2. Select everything (`Ctrl+A`) and paste this over it completely:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <application
        android:label="SALU Remote"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="salu" android:host="pair" />
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

3. `Ctrl+S` to save.

What this did, in one line each: internet (to reach the PC), camera (for the QR scanner
later), the app's name becomes "SALU Remote", and the phone is allowed to talk to your PC
in plain local traffic.

#### 4.2 Raise the minimum Android version

1. Open `android` → `app` → **`build.gradle.kts`** (if you only see `build.gradle`, use
   that one — the change is the same idea).
2. Find the line (around the middle):

```kotlin
        minSdk = flutter.minSdkVersion
```

3. Change it to:

```kotlin
        minSdk = 24
```

(In the older `build.gradle` style the line reads `minSdkVersion flutter.minSdkVersion` and
you change it to `minSdkVersion 24`.) Save.

#### 4.3 Keep the phone screen awake

1. Open `android` → `app` → `src` → `main` → `kotlin` → `app` → `salu` → `salu_remote` →
   **`MainActivity.kt`**.
2. Select everything and paste this over it:

```kotlin
package app.salu.salu_remote

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val screenChannel = "app.salu.remote/screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

> **Important:** the **first line must stay as your file had it.** If your first line says
> something other than `package app.salu.salu_remote`, keep *your* version. Only the rest
> changes.

3. Save. (You do not need `android/gradle.properties` — that one is only if a build later
   fails with "Java heap space". Ask me then.)

---

### Part 5 · Run it and pair with SALU

#### 5.1 Get dependencies and start the app on your phone

Because this checkout now uses `shared_preferences` to remember the pairing, run this once
in Android Studio's Terminal (from the repository root):

```bash
flutter pub get
```

Then pick your phone in the device dropdown at the top and press the green **Run ▶**.
First build is slow (2–5 minutes); after that, seconds.

You should see a dark screen titled **SALU Remote** with a **Connect to your PC** card and
two boxes: *PC address* and *Pairing code*.

#### 5.2 Get the address and code from the PC

1. Start **SALU** on the PC and play something (or just leave it open).
2. Right-click on the picture → the little strip at the bottom-right → click **Remote**
   (the last icon).
3. The panel shows a line like `● Connected · Wi-Fi · 192.168.0.12 · 7258` and a code like
   `7K4M-QP2X`. The phone wants exactly those two things:
   - **PC address box** → `192.168.0.12:7258` (address, colon, port — as shown)
   - **Pairing code box** → `7K4M-QP2X` (dashes are fine, either way works)

#### 5.3 Connect

Press **Connect** in the app. Within a second the top of the app changes from
*Connecting…* to a **green dot + Connected**, and the title becomes your PC's name.

Press **Play ▶**. The PC should pause. Press it again — it plays. Try the **10-second**
buttons, the **volume** slider, **Mute**, **Shuffle**, **Repeat**. Every button moves the PC
immediately, and the title/time in the app follows what the PC is doing.

**That is the whole loop working.** From now on, the app remembers your PC: next time you
open it, it connects by itself and goes straight to the controls.

---

### Part 6 · If something goes wrong

Look up your symptom, try the fix, and if it still fails send me the two things in §7.

| What you see | What it means / do |
|---|---|
| `flutter` is not recognised as a command | Flutter is not on your PATH. Close and reopen the terminal after installing; if it still fails, send me the output of `flutter doctor`. |
| Android Studio cannot see your phone | USB debugging still off, or the cable is charge-only. Turn on *Developer options → USB debugging*, unlock the phone screen, and accept the "Allow USB debugging?" prompt. |
| The app says *"No answer from 192.168…"* (nothing came back in 8 seconds) | The packets are being **dropped silently**, which on a home network is almost always **Windows Firewall**. Allow SALU on **Private** networks (the PC's Remote panel has an **Open firewall settings** button), and check the Wi-Fi network profile on the PC is *Private*, not *Public*. Then make sure the phone is on the **same Wi-Fi** as the PC — not mobile data, not a guest network. **Quick test from the phone:** open the phone's browser and go to `http://<PC address>:<port>/` (e.g. `http://192.168.0.12:7258/`). If SALU is reachable you get an instant blank/forbidden page; if the browser spins and times out, it is the firewall or the network — nothing in the app can fix that. |
| The app says *"192.168… answered, but nothing is listening on port …"* | The PC is reachable, but SALU is not listening there: SALU is closed, **Remote** is switched off in SALU's Settings → General, or the port differs from the one in the PC's Remote panel (SALU falls back to 7259–7267 when 7258 is busy). |
| The app says *"Can't reach 192.168…"* | The phone and the PC are not on the same network — no route to that address at all. Check the phone's Wi-Fi. |
| The app says *"That pairing code is not valid"* | The code changed. It rotates every time you close the PC's Remote panel, and after every successful pairing. Reopen the panel and use the code it shows now. |
| The app says *"This phone is no longer paired"* | The PC forgot this phone (you removed it in SALU, or reinstalled SALU). The app drops the old pairing by itself — type the current code from the PC's Remote panel once. |
| It connected on the PC but the phone keeps saying *Connecting…* | **Windows Firewall** is blocking SALU. In the PC's Remote panel there is a hint line with **Open firewall settings** after 90 seconds — allow SALU on **Private** networks. |
| The camera opens but never reacts to the QR | Fixed in the app (the scanner was never told to listen). Update the app; then aim so the whole QR sits inside the bright square. A QR that is *not* SALU's now says so on screen instead of staying silent. |
| Everything worked yesterday, dead today | The PC's IP changed (the router reassigned it). Open the PC's Remote panel, read the new address, and type it into the app's *PC address* box. |
| Red text in Android Studio under a file | Send me a screenshot of the file name and the red line. Do not "fix" it yourself. |
| The build fails with `Java heap space` | Tell me — I will give you the one-line change for `android/gradle.properties`. |
| Build stops with `Error: Gradle build failed due to Java/Gradle incompatibility` (a bare version like `25.0.3` under `What went wrong:`) | The Gradle the checkout pins is older than the Java Flutter builds with. **Already fixed here** — the repo now uses Gradle `9.3.1` + AGP `9.1.0` + Kotlin `2.4.0` (Flutter 3.47's own template numbers, good for Java 17–25). Just `git pull`, then `flutter clean` and press Run again. Walkthrough: **README → “Build fails: Gradle build failed due to Java/Gradle incompatibility”**. Do not downgrade those three versions, and do not edit `android/gradle.properties` to point at a JDK — that is the temporary workaround, not the fix. |

---

### Part 7 · What to send me when it breaks

Three things, always the same three:

1. **A photo/screenshot** of the phone screen (or the exact words it shows).
2. The **first red block** in Android Studio's `Run` panel at the bottom (scroll up to the
   first red text, not the last).
3. If it says "Connected" but nothing moves: what you pressed, and whether the PC did
   anything.

With those I can tell you what to change without guessing.

---

### Part 8 · What comes next (so you know where this is going)

Each part below arrives as **more files under `lib/`** that you paste the same way — plus,
sometimes, one or two new lines in `pubspec.yaml`. The app is never broken between parts.

1. **QR scanner** — point the phone camera at the PC's QR and pairing happens by itself.
2. **The real SALU interface** — the three tabs (`Play` · `Browse` · `Tune`), the header,
   the playlist card, the drawn icons, Focus mode.
3. **Browse** — your PC's folders, and your saved stream URLs.
4. **Tune** — equalizer, subtitles, audio tracks.
5. **Web mode** — driving the PC's browser page from the phone.

Tell me when Part 5 works on your phone, and I will send the next part in exactly this
format: *where to click, what to type, what to paste.*

---

# Part 3 · PC-side protocol and implementation specification (§1 – §17.15)

> *(This Part was the whole of `remote.md`; its headings are one level deeper than they used to be, its section numbers are unchanged.)*

> **2026-09-26 extension:** `pc_part.md` Part F defines the capability-gated,
> revisioned `queue_groups_page` protocol used by the current Remote. It supersedes
> legacy `start + count` group membership. PC implementation is still pending;
> Remote uses a safe flat view until that capability is advertised.


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

### 1. The locked decisions

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

#### Decisions I made on your behalf — flip any of these, they are cheap to change

| # | Decision | Why |
|---|---|---|
| A1 | Remote commands **do** show OSD cards on the PC screen — **except volume and mute** (you are already looking at your phone for those). | Seeing `>> +15s` on the PC is reassuring; seeing a volume card flash on the TV from across the room is not. |
| A2 | **"Control" is informational, not a lock.** Any paired phone may send a command; doing so makes it the shown controller. No allow/deny popups. | Two paired phones belong to the same person. A permission dance is friction for zero security. |
| A3 | **No absolute file paths** are sent to the phone — title only. | The phone never needs `D:\Movies\…`, and it is one less thing to leak. **⚠ Revised 2026-09-20 (v1.1):** the user asked for a file browser on the phone, so paths now travel **on demand, by explicit taps, to an authenticated device**, behind a separate switch — see §17.6. Paths are still never part of the automatic state snapshot. |
| A4 | The QR panel is a **centered modal dialog**, same recipe as `OpenUrlDialog` / Settings. | The QR must be big enough for a camera, and pairing deserves full attention. No new `PanelService` popup tier needed. |
| A5 | Pairing **code rotates when the panel closes** (and immediately after a successful pairing). The code never changes while the panel is on screen. | A QR photographed over someone's shoulder stops working; a user mid-scan is never sabotaged by a rotation. |
| A6 | The APK project lives **outside** this repo for now; the shared protocol file is copied with a "do not edit separately" header. | Keeps this repo clean while the APK's UI is still being designed. Revisit later (§16). |

---

### 2. Non-goals for this phase

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

### 3. Why this is small work in this codebase

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

### 4. Architecture

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

### 5. File map

#### 5.1 New files

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

#### 5.2 Edited files (exact insertion points)

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

#### 5.3 Exact sizes for the strip (do the arithmetic once, never guess)

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

### 6. The protocol (v1)

All messages are one JSON object per WebSocket text frame. **Unknown fields are always
ignored** (forward compatibility). Maximum message size: 8 KB.

#### 6.1 Handshake

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

#### 6.2 Commands and replies

```json
{"type":"cmd","id":7,"verb":"seek_to","args":{"position":123456}}
{"type":"ack","id":7,"ok":true}
{"type":"error","id":7,"code":"nothing_playing","message":"Nothing is playing on the PC."}
```

- `id` is client-generated and only has to be unique per connection.
- Every `cmd` gets exactly one `ack` **or** one `error`. Never neither.
- `args` is optional; unknown args are ignored.

#### 6.3 State

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

#### 6.4 Errors and close codes

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

### 7. Server behaviour, in detail

#### 7.1 Pairing and security

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

#### 7.2 Snapshot sending — two clocks, one builder

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

#### 7.3 Rate limiting

30 commands/second per device, counted in a 1-second sliding window; over the limit
the command is dropped with `too_fast` and the log gets one line. This exists to
contain a buggy client, not an attacker.

#### 7.4 `TransportActions` — the only changes

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

#### 7.5 Web mode and focus (D8)

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

### 8. Networking details that decide "it just works"

#### 8.1 Port

- **Preferred: `7258`** — `S-A-L-U` on a phone keypad. Memorable, easy to write a
  firewall rule for.
- If busy: try `7259 … 7267`, then finally let the OS pick (port `0`).
- **The QR always carries the real bound port.** The phone never assumes a fixed port.
- Persist the preferred port later (P2); v1 keeps it in memory only.

#### 8.2 Multiple adapters — the bug that eats an evening

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

#### 8.3 Windows Firewall — the #1 support ticket

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

#### 8.4 Logging

One consistent prefix, matching the repo's existing style:

```
[SALU] remote: listening on 0.0.0.0:7258 (Wi-Fi 192.168.0.12)
[SALU] remote: Pixel 7 paired (a1b2c3)
[SALU] remote: auth failed from 192.168.0.77 (bad_code)
[SALU] remote: rejected 203.0.113.9 (not a private address)
[SALU] remote: stopped (toggle off) — 2 phones remembered
```

---

### 9. Command table (v1)

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

#### Reserved for v2 (do not implement now, but leave the door open)

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

#### Snapshot plumbing

`RemoteService` listens to these and marks the state dirty:
`PlayerService`'s `transportState`, `isPlaying`, `hasMedia`, `currentTitle`,
`position`, `duration`, `volumeLevel`, `isMuted`, `isBuffering`, `shuffleOn`,
`repeatMode`; `BrowserService.mode`; `WindowStateService.mode` + `isFullscreen`;
`QueueService.items`; `OsdController.current` (v1.1 — the deck's one slot, which is
what the Resume toast appears on, §17.5); plus its own device/controller notifiers.

---

### 10. PC-side UI

#### 10.1 The QR option in the right-click strip (D9)

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

#### 10.2 The Remote panel (`lib/ui/osc/remote_panel.dart`)

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

#### 10.3 Settings → General → Remote section

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

### 11. Lifecycle and persistence

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

### 12. Auto-discovery (P3 — the bonus, build only after R4)

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

### 13. Build order and acceptance criteria

#### R1 — Server + protocol, proven from a terminal (no Android at all)

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

#### R2 — The PC UI

`QrMark`, the strip item + widths, the panel, the Settings section, `main.dart` wiring.

**Done when:** the QR renders on white, the toggle starts/stops the server live, and
forgetting a phone blocks it on its next connect.

#### R3 — Resilience

Firewall hint, address picking (§8.2), status copy for every state, ping-interval
reaping, rate limiting, the extra unit tests.

**Done when:** a phone can be killed, the PC can sleep, and the next connection is
correct in the first frame.

**R1 and R2 are the whole deliverable.** The APK is a separate project after that.

---

### 14. Test plan

#### Unit tests (repo convention: `test/<name>_test.dart`)

| File | Covers |
|---|---|
| `remote_protocol_test.dart` | Build/parse round trips, unknown fields ignored, version mismatch, error codes, `rev` monotonicity helper. |
| `remote_pairing_test.dart` | Code alphabet has no `0/O/1/I/L`; code rotation on panel-close and on pairing; token hash match/mismatch; device store add/forget/last-seen. |
| `remote_network_test.dart` | Private-range filter; virtual-adapter rejection; Wi-Fi > Ethernet ranking; empty result path. |
| `remote_snapshot_test.dart` | `RemoteSnapshot.fromValues({...})` — a pure function over plain values, so no mpv engine is needed (`test/tune_fake_engine.dart` shows the house style for this). |
| `right_menu_test.dart` *(extend)* | Five items on the full canvas, three in channel mode, widths 198/118, the QR mark opens the door. |

#### Manual checklist

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

### 15. Troubleshooting table (put this in the release notes)

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

### 16. Open questions (deliberately left open)

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

### 17. Expanded scope — v1.1 (added 2026-09-20)

Everything here comes from the user's second round of requirements: the phone must also
browse the PC's files, load the saved M3U/stream list and a typed URL, drive the full
equalizer, drive the full subtitle engine (including OpenSubtitles search and download —
**the download happens on the PC**), and switch/mirror the Player↔Web mode.

The APK's screens for all of this are designed in `remote_apk_ui.md`.

#### 17.1 What this supersedes

| Earlier statement | Now |
|---|---|
| §2 "Controlling the PC's browser — v2", "Queue browsing / channel lists — v2" | **In v1.1.** Basic web navigation + the file browser + the URL library are specified below. |
| A3 — "no absolute paths to the phone" | **Revised.** Paths travel on demand, to authenticated devices, behind `remote_file_access` (§17.6). Never inside the state snapshot. |
| §9 "Reserved for v2" | Mostly moved here; the list keeps only what is genuinely still v2. |
| Permanently out | phone-side playback, screen preview, **image thumbnails**, **delete/rename/move/upload**. Do not design these in. |

#### 17.2 The rule that keeps the snapshot cheap

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

#### 17.3 New and changed PC files

| File | Change |
|---|---|
| `lib/core/remote/remote_fs_service.dart` | **New.** Drive list from the Win32 drive table (`GetLogicalDrives` + `GetDriveTypeW` — **never** probed with `Directory.existsSync`; network and UNC letters are filtered out of the table before any file-system call can touch them, so disconnected mapped drives cannot stall the answer), pinned places, directory listing with the media filter (`MediaUtils.isMedia` / `DropHandler.scanFolderForMedia` for whole folders), subtitle filter (`.srt .ass .sub .vtt`), system-folder hiding, sort, paging, path validation. Read-only: **no write API exists in this file at all**, by design. |
| `lib/core/remote/remote_browser_bridge.dart` | **New.** Mirrors the browser's active tab into `BrowserService` and routes remote nav commands back to the live `BrowserScreen` (§17.7). |
| `lib/core/remote/remote_web_media_bridge.dart` | **New.** Drives the active web page's own `<video>`/`<audio>` element by JavaScript injection — play/pause, position, volume, mute, fullscreen (§17.11). Follows the existing `WebTab.executeScript` pattern (`_pauseAllMediaJs`, the exit-fullscreen script) — 2 s timeout, errors swallowed. Updated 2026-09-23 (pc_part.md A1/A2): the wire units (ms + percent) convert at the script edge, `NaN`/`Infinity` sanitize to `0` + `seekable:false`, writes clamp, and the element pick prefers a playing/visible element while ignoring hidden/zero-box/sub-2-second clips. |
| `lib/core/remote/remote_web_focus_bridge.dart` | **New (2026-09-23).** `web_key` + `web_focus_get` (pc_part.md A3 · §17.13.5): the page's own tab order, arrow/Enter/Escape semantics with the caret rule, and the injected focus ring — pure script builders + a thin `executeScript` adapter, unit-tested without a WebView. |
| `lib/core/remote/remote_command_handler.dart` | Extended with the §17.4 verbs, plus (2026-09-23) `web_tabs_get` / `web_tab_activate` / `web_tab_close` / `web_tab_new` / `web_bookmarks_get` / `web_key` / `web_focus_get` (pc_part.md A3–A5), plus (2026-09-24) `web_fullscreen` / `web_mouse_move` / `web_mouse_click` / `web_bookmark_add` and `browser_nav {action:"home"}` (pc_part.md C1–C4). |
| `lib/core/browser_service.dart` | **Extended (2026-09-23).** The tab-strip mirror (`List<WebTabMirror>` + write-side tab handler) and the focus-script seam (pc_part.md A4/A3), on top of the §17.7 scalar mirror. |
| `lib/core/remote/remote_input_service.dart` | **New (2026-09-24).** The trackpad's PC half (pc_part.md C3 · §17.14.3): Win32 `SendInput` **relative** moves (CSS px × the window's DPR, sub-pixel remainder carried, ±320 px clamp, no gain of its own) and real button down/up clicks in one batch; `no_web_mouse` when the input is blocked; an injectable seam so the maths is unit-tested. |
| `lib/core/remote/remote_web_media_bridge.dart` *(again)* | **Extended (2026-09-24).** `RemoteWebFullscreen` — the one fullscreen seat's plan (§17.14.1): injected request → read-back → a real click on the player's own control → the SALU window only when the page has no reachable player; `on:false` leaves both. `web_media_get` gains `fullscreen`. |
| `lib/ui/screens/browser_screen.dart` | **Extended (2026-09-24).** Installs the page-click / page-exit legs for the active tab, answers `browser_nav {action:"home"}` with its own Home button, and resolves a `web_tab_new` address the omnibox way (`youtube.com` → `https://youtube.com`) so a new tab is never blank (pc_part.md C1/C2/C5). |
| `third_party/webview_windows` | **Delta 3 (2026-09-24, Dart only).** `WebviewController.sendMouseClick` — a trusted click through the composition controller's `SendMouseInput`, the path the physical mouse already takes (VENDOR_NOTES.md). |
| `lib/core/subtitle_service.dart` | **Small addition:** expose the engine's state as public read-only getters/notifiers — whether a key is configured, whether it is signed in, and the quota/auth pauses (today `_quotaPaused` / `_authPaused` are private). The phone must be able to say *"sign in on the PC"* instead of silently failing. |
| `lib/ui/osc/` | *(nothing)* — the remote panel gains one row (§10.3). |

**No changes needed:** `TuneService` already exposes everything (`setBandGain`, `selectStop`,
`resetBands`, `applyMy`, `saveMy`, `eqStop`, `eqCustom`, `mySlot`, `fileKind`, `autoPick`) and
already coalesces EQ writes at `eqWriteGap = 120 ms`; `PlayerService` already exposes
`selectAudioTrack`, `selectSubTrack`, `setSubDelay`, `loadSubtitleFile`; `SubtitleService`
already exposes `search` / `save` / `saveAndLoad`; `OpenMediaService.playUrl` already handles
"URL vs M3U vs web link" plus health marking. **The remote is still an adapter.**

#### 17.4 Verbs added in v1.1

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
| `browser_nav` | `{action:"back"\|"forward"\|"reload"\|"stop"\|"home"}` | routed through the browser bridge (§17.7); `home` (added 2026-09-24) is the screen's own home action — the loaded page goes to its site's front page, same tab (§17.14.2) |
| `browser_open` | `{url}` | `BrowserService.openInBrowser(url)` (switches to Web mode itself) |
| `web_fullscreen` | `{on?}` | **One fullscreen seat, the PC picks the target** (added 2026-09-24): the page's own player when the page has one, the SALU window when it has not — `ack {fullscreen, target:"page"\|"window"}` (§17.14.1) |
| `web_mouse_move` | `{dx, dy}` | relative pointer movement on the **PC's own pointer** (added 2026-09-24), CSS pixels, no acceleration — the phone already applied the gain (§17.14.3) |
| `web_mouse_click` | `{button, count}` | a real click at the current pointer position (§17.14.3) |
| `web_bookmark_add` | `{url, name?}` | **add-only** bookmark append (§17.14.4) — never rename, never delete |
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
| `web_media_get` | — | inject a read script → `{found, playing, position, duration, volume, muted, canFull, fullscreen, seekable, unit}` (`found:false` when the page has no reachable media element). `canFull` = *possible*; **`fullscreen`** (added 2026-09-24) = in fullscreen **right now** — the phone's fullscreen mark reads it (§17.14.1) |
| `web_media_toggle` | — | inject play/pause on the media element |
| `web_media_seek` | `{to}` or `{delta}` | set `currentTime` — **both in milliseconds**, `{delta}` relative to now |
| `web_media_volume` | `{percent}` | `element.volume = percent/100` — **integer percent 0–100**, the page player's own volume, never the Windows volume |
| `web_media_mute` | `{on}` | `element.muted = on` |
| `web_media_fullscreen` | — | `requestFullscreen()` / `exitFullscreen()` on the element's container. **Superseded by `web_fullscreen`** (2026-09-24, §17.14.1) — kept because the phone still uses it as the older-PC fallback |

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

#### 17.5 Snapshot additions (small, never big)

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

#### 17.6 Security, privacy and the new switch

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

#### 17.7 The one real refactor: mirroring the browser

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

#### 17.8 Errors added in v1.1

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

#### 17.9 Tests and checklist additions

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
29. **(2026-09-24) The mode flip, both ways.** With the **Play** tab up, tap the mode pill's
    **Web** seat → the phone's Play tab becomes the web body *and the Browse seat greys in
    the same frame* (no tab change, nothing else repainted). Tap Browse → one line, *"Files
    and Streams are Player-only — the PC is in Web mode."* Now tap the pill's **Player**
    seat → SALU leaves the browser, the Play tab cross-fades back to the player, **and the
    Browse seat un-greys with it**: tapping it opens Files and says nothing about Web mode.
    Then repeat the pair from the **Tune** tab, where no bounce is involved at all. (The
    seat used to stay grey after the return until some unrelated tab change repainted the
    bar — `remote_apk_ui.md` §2.1, `test/browse_seat_test.dart`.)

#### 17.10 Build-order impact

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

#### 17.11 Web media — how it works, and where it honestly fails

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

#### 17.12 Decisions recorded from the user's answers (2026-09-20)

| # | Question | Decision |
|---|---|---|
| 1 | File browsing default | **ON** — as proposed (§17.6). |
| 2 | Multi-select | **In scope**, designed in the APK doc §5.1: per-row `▶`/`＋` quick actions, long-press checkbox mode with select-all/deselect, bottom action bar. PC impact: none — `fs_open` already takes a `paths` array (cap 500). |
| 3 | EQ in landscape | Assistant's call: **yes, EQ-only landscape** (mixing-desk layout). No PC impact. |
| 4 | Queue card vs screen | It is the **playlist**: collapsible card, auto-scroll to the current row, **5 rows visible max**, tap a row to jump. PC impact: `queue_get` + `queue_jump` promoted into v1.1 (§17.4, built with R1). |
| 5 | Speed | Assistant's call: **in, as a chips row at the bottom of Tune → Equalizer** (the PC's own stops). PC impact: `speed_set` + `"speed"` in the snapshot's tune block (§17.5). |
| 6 | Activity indicator | Assistant's call: **yes** — one quiet dot in the header, phone-side only, no PC impact. |
| + | Web media | **New rule:** Web mode + page playing media ⇒ only play/pause, seek, volume, mute, fullscreen (§17.11). PC impact: `remote_web_media_bridge.dart` + the `web_media_*` verbs + `hasMedia` in the snapshot. |

#### 17.13 Web tabs, bookmarks and the focus pad (added 2026-09-23)

> **Superseded in part, 2026-09-24 (§17.14).** The phone no longer has a D-pad — the Tune
> tab in Web mode is a **trackpad** (`lib/ui/mouse_pad.dart`) and the double tap still sends
> `web_key {key:"Enter"}`, so the `web_key` verbs below keep their meaning and their ring.
> The **open-tab list** is no longer a sheet reached from the nav row: it is a collapsible
> section at the foot of the Web body (`lib/ui/web_tabs_card.dart`), built exactly like the
> queue card. The verbs, the mirror and the size rules below are unchanged.

**Why this exists.** The phone's Web body grew the doors the couch user actually asked
for: the **open-tab list** with a close button on every row, **new tab**, the **saved and
bookmarked pages**, **−10 s / +10 s** on the page's own player, live seek and volume bars,
and a **D-pad that says what it is about to click**. The phone side is built in
`salu-remote` (its `lib/ui/web_body.dart`, `lib/ui/web_sheets.dart`, `lib/ui/web_tabs_card.dart`);
everything it needs from the PC is specified here, and `pc_part.md` is the work order that
walks through it file by file.

**Feature flags, not a version bump.** `proto` stays `1` and every verb here is additive.
The PC advertises what it implements in `hello.features` —

| Feature | Means | Phone behaviour without it |
|---|---|---|
| `web_media_unit` | `web_media_get` speaks §17.4's units (ms + percent) and says so with `unit` | The phone reads the units off the reply itself and answers in kind — usable, but a bridge, not the design |
| `web_tabs` | `web_tabs_get` / `web_tab_activate` / `web_tab_close` / `web_tab_new` | The **Open tabs** section says *"This PC does not report its tabs yet"* and its ＋ still opens a URL (`open_url`) |
| `web_bookmarks` | `web_bookmarks_get` | ☆ Saved pages says the PC does not report its bookmarks yet; **Save this page** still works, into SALU's own list (§17.14.4) |
| `web_key` | `web_key` + `web_focus_get`, **and the focus ring is drawn** | The trackpad's double tap becomes a double click instead of Enter; the ring is what makes the focus visible while it is drawn |

An older PC and a newer phone therefore still talk, with fewer buttons — never with dead
ones.

##### 17.13.1 The tab strip has to move into `BrowserService`

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

##### 17.13.2 The verbs

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

##### 17.13.3 Size discipline

The frame budget is 8 KB (§6.2) and a tab strip is a list of strings — the one place this
protocol can genuinely overflow. So: **cap the list** (send at most 50 tabs, and say the
real total in `count`), **truncate** each `title` to 80 characters and each `url` to 180,
and never send favicons, histories or anything encoded. Bookmarks the same way: at most 200
entries, titles 80 / urls 180, folders one level deep. If a list would still not fit, send
fewer rows — the phone renders what arrives and shows `count` as the truth.

Neither list ever rides the snapshot. The snapshot keeps its single scalar `web.tabs`,
which is what the phone's nav row shows before anything is asked for.

##### 17.13.4 Bookmarks, read-only

`web_bookmarks_get` mirrors whatever the PC's browser already keeps as its own
bookmarks/ favourites — read-only, because a phone that can silently rewrite the PC's
bookmark bar is a phone that can lose it. If the browser has no bookmark store, do **not**
advertise `web_bookmarks`: the phone then shows SALU's URL library alone, which is already
a complete "saved pages" feature (`library_get` / `library_add`, and the Web body's
**Save this page** writes the current URL and title into it).

##### 17.13.5 `web_key` and the focus ring

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

#### 17.14 Home, one fullscreen seat, and the mouse (added 2026-09-24)

**Why this exists.** The user used the phone's Web section on real sites and reported five
things, plus one request for the Tune tab. In their words:

1. *"from remote fullscreen button making salu fullscreen for other video stream except
   youtube which is not getting fullscreen when press fullscreen at remote."*
2. *"at previous page icon place home icon which bring current loaded page to its homepage
   as salu do."*
3. *"at the same row very right you placed open tab button. i need that thing will show below
   volume bar and there will be heading 'open tab' just like queue for normal player and will
   have collapse/expand option like queue."*
4. *"new tab opening for url and when i am typing url then press open tab its opening blank
   tab."*
5. *"at web saved pages option showing bookmark but also showing m3u list from player
   section. this is not correct only bookmark should show as it is web section."*
6. Tune tab, Web mode: *"i need to remove this and everything. after removing it will be
   mouse pad as laptop has a nice bounding box will be shown which will be track pad. by
   touching there will activate mouse at salu and double tap will be enter. below track pad
   will be simple one line."*

**2, 3 and 5 are phone-only** and are already built in `salu-remote`
(`lib/ui/web_body.dart`, `lib/ui/web_tabs_card.dart`, `lib/ui/web_sheets.dart`):
**Home** was *added* to the nav row (Home · Back · Forward · Reload · Fullscreen —
nothing was replaced), the open tabs became a **collapsible section** at the foot of the
body headed *Open tabs* with a count and a chevron (the queue card's own shape, the queue
card's own remembered open/closed state), and **☆ Saved pages** now lists the PC browser's
bookmarks **only** — SALU's own m3u list is the player's list and no longer appears in a
sheet reached from the browser.

**1 and 4 need work on the PC, and 6 needs three new verbs.** The phone side of all of it is
written and degrades honestly; `pc_part.md` Part C is the file-by-file work order.

##### 17.14.1 One fullscreen button — `web_fullscreen`

**The bug, exactly.** The phone had one fullscreen seat doing two jobs, chosen by whether it
could *find* the page's player:

| Page | Old behaviour | What the user saw |
|---|---|---|
| YouTube (player found) | the phone sent `web_media_fullscreen` → the bridge injected `requestFullscreen()` | **nothing.** A browser refuses `requestFullscreen()` unless the call is tied to a real user gesture, and an injected script is not one |
| any other stream (player not found, or behind an iframe) | the phone sent `fullscreen_toggle` → `WindowStateService` | the **whole SALU window** went fullscreen, which is not what "fullscreen this video" means |

**The rule now.** One verb, and **the PC decides what goes fullscreen**:

| Verb | Args | Reply | Meaning |
|---|---|---|---|
| `web_fullscreen` | `{on?: bool}` | `ack {fullscreen: bool, target:"page"\|"window"}` | **The phone sends it with no arguments — a toggle**; `{on}` is in the contract so any client (and the PC's own tests) can ask for one direction explicitly. `target:"page"` = the page's own player is (or went) fullscreen; `target:"window"` = the SALU window did |

The PC's order of preference, and it must be this order:

1. **The page's player, if the page has a reachable one** (`hasMedia` / the §17.11 find
   script). Ask the element's container for fullscreen **and make it stick**: WebView2
   refuses a `requestFullscreen()` that carries no user activation, so when the injected call
   is rejected, the PC clicks the page's *own* fullscreen control with a **real simulated
   input** (the same `SendInput`-class path the PC already owns) — a real click *is* a
   gesture, so YouTube's own player obeys, which is the half of this bug the user noticed
   first.
2. **The SALU window, when the page has no reachable player** — the honest fallback the user
   described as *"making salu fullscreen for other video stream"*: keep that behaviour, but
   only *after* the page's own player has been ruled out, never instead of trying it.
3. **`on:false` always leaves** — exit element fullscreen if it is on, then the window.
   Never leave the user in a full-screen state with a button that no longer exits it.

**And the host has to cooperate.** In WebView2 an element entering fullscreen raises
`ContainsFullScreenElementChanged`, and **the host app is responsible for filling the screen**
— a page that goes fullscreen while the host does nothing *looks* like nothing happened. So
SALU's browser layer must listen for that event and enter its own fullscreen while it is
true, exactly as it must leave it when the element's fullscreen ends (the PC's own Esc
handling in `BrowserScreen` already touches this).

**Tell the truth about the state.** `web_media_get` gains `fullscreen: bool` — whether the
element is *in* fullscreen right now (as opposed to `canFull`, which only means *possible*).
The phone's seat draws `web.fullscreen || window.fullscreen || the element's own reading`,
so a PC that answers `fullscreen:true` shows the exit mark even if the snapshot lags.

**Degradation.** A PC without `web_fullscreen` keeps exactly today's behaviour: the phone
falls back to the old split (media found → `web_media_fullscreen`, else → `fullscreen_toggle`)
when it sees `unknown_command` or `invalid_arguments` on the first press. That is the buggy
path, but it is better than a dead button — and it disappears the moment the flag appears.

##### 17.14.2 Home — `browser_nav {action:"home"}`

One new action on the verb that already exists:

| Verb | Args | PC call |
|---|---|---|
| `browser_nav` | `{action:"back"\|"forward"\|"reload"\|"stop"\|**"home"**}` | routed through the browser bridge (§17.7), `home` = the screen's own home action |

**What "home" means is the PC's decision, in this order:** SALU's configured home page if the
browser has one; otherwise **the origin of the URL loaded in the active tab**
(`https://www.youtube.com/watch?v=…` → `https://www.youtube.com`), navigated **in the same
tab** — not a new tab, not `browser_open`. A page with no origin (`about:blank`, a `file://`
page) answers `ack` and does nothing; that is not an error.

An unknown action keeps answering `invalid_arguments` (it always has), and the phone then
falls back to `browser_open {url}` with the origin it can compute itself — so the seat works
on an older PC too, at the cost of possibly a new tab.

**Advertise `web_home`** in `hello.features` when the action is implemented.

##### 17.14.3 The trackpad — `web_mouse_move` / `web_mouse_click`

The D-pad is gone from the phone (its `web_key` verbs stay: the double tap still sends
`Enter`, and Esc keeps its documented job on the PC). The Tune tab in Web mode is now **a
trackpad, two scroll arrows and one line**, and it drives **the PC's own pointer** — the real cursor, moving
across the real screen, which is the only feedback that makes a pointer feel like a pointer.

| Verb | Args | Reply | PC call |
|---|---|---|---|
| `web_mouse_move` | `{dx, dy}` — **relative**, in CSS pixels, signed, `0` allowed | `ack` (`{x,y}` if it is cheap) | `SendInput`-class **relative** pointer movement over the WebView, by exactly `dx`/`dy` device pixels (scale by DPI, do not accelerate — the phone already applied the gain) |
| `web_mouse_click` | `{button:"left"\|"right"\|"middle", count:1\|2}` | `ack` | a real click at the current pointer position, `count` times. Injecting `element.click()` is **not** an acceptable implementation: the point of a mouse is that it works on canvas players, video overlays and DOM buttons alike |

**Rules that make it usable, all measured on the phone side already**
(`lib/ui/mouse_pad.dart`):

- **Batched, never queued.** The phone accumulates travel and sends **one packet per 40 ms
  (≈25 commands/s)**, with at most two unanswered packets in flight — inside the 30 cmd/s
  budget with room for the 1/s media read and a ping, and no stack of stale movement behind a
  slow PC.
- **The phone converts the thumb; the PC obeys.** Travel is already multiplied by the pad's
  gain (2.5×, so one comfortable swipe crosses a page) and clamped to ±320 px per packet. The
  PC must **not** add acceleration on top.
- **`web_mouse_move` must never block** the command isolate: move, ack, next. A dropped
  packet is invisible; a one-second stall is not.
- Movement answers `no_web_mouse` only when it truly cannot be delivered (no injectable
  input, session locked). `unknown_command` tells the phone to stop asking and say so in its
  one line.
- **Advertise `web_mouse`** only when both verbs work.

The phone's gestures, for the record: **drag = move**, **single tap = left click**,
**double tap = Enter** (the user's own choice — `web_key {key:"Enter"}`, so a page that
manages its own focus still gets a real activation; a PC without `web_key` gets a double
click instead).

**Two scroll seats under the pad (added 2026-09-24 — phone-only, no new verb).** The user
asked for up/down buttons that scroll the page, and for the pad to shrink from 70% to 60% of
screen height to make room for them. Both are done on the phone alone:

| Seat | Args | Meaning |
|---|---|---|
| ▲ / ▼ under the pad | `web_key {key:"ArrowUp"\|"ArrowDown"}` | the page's own arrow key, once per tap — **§17.13.5 semantics unchanged** |

- **No PC change, and no new feature flag.** The arrows are the old D-pad's keys, still
  specified and still implemented; only their seat on the phone was missing. A build that
  advertises `web_key` accepts these focus-walk arrows; one that does not gets greyed seats,
  and the one-line caption names the missing feature(s). `web_mouse` and `web_key` are now tracked as
  **separate** promises on the phone, so a `web_key` refusal no longer silences the trackpad.
- **This is a focus walk, not a scroll step** (§17.13.5), which is the honest trade for
  costing nothing: on an ordinary page the page scrolls to keep the focused element centred;
  in a text field the arrows move the caret, and a page with nothing focusable may not move.
  One tap = one key, and **no hold-to-repeat** — repeated focus walks can race through the
  page's focus order instead of giving a measured scroll step.
- **If this proves jumpy on real sites**, the fix is a wheel verb (`web_mouse_scroll {dy}`,
  `SendInput` + `MOUSEEVENTF_WHEEL` in `remote_input_service.dart`, advertised as
  `web_scroll`) — a few lines beside the trackpad's existing input path, but PC work, and so
  a separate work order in `pc_part.md`.
- **Rate.** Human tapping, a few commands a second at worst — no batching, no queue, and
  nothing taken from the 30 cmd/s budget the trackpad's 25/s already lives inside.

##### 17.14.4 Add-only bookmarking — `web_bookmark_add`

☆ Saved pages is bookmarks only now (§17.14, item 5), which makes **Save this page** useful
only if the saved page shows up *in that list*. So the phone may append to the PC's bookmark
store — and nothing else:

| Verb | Args | Reply | Errors |
|---|---|---|---|
| `web_bookmark_add` | `{url, name?}` | `ack` (`{entry:{name,url,folder}}` if it is cheap) | `no_web_bookmarks`, `invalid_arguments` |

**Add-only is the whole safety property** (§17.13.4): no rename, no delete, no reorder, no
"sync". A URL already in the store is a no-op, not a duplicate. If the browser has no
bookmark store at all, do not advertise `web_bookmark_add` and do not advertise
`web_bookmarks`; the phone then saves into SALU's own list and its snackbar says so, because
a save the user cannot find again is worse than no save.

**Advertise `web_bookmark_add`** in `hello.features` when it is implemented.

##### 17.14.5 The feature flags added here

| Feature | Means | Phone behaviour without it |
|---|---|---|
| `web_home` | `browser_nav {action:"home"}` | the Home mark falls back to `browser_open {url}` with the page's own origin (may open a tab) |
| `web_fullscreen` | `web_fullscreen` = one seat, the PC picks page vs window | the old split comes back: `web_media_fullscreen` when a player was found, `fullscreen_toggle` otherwise |
| `web_mouse` | `web_mouse_move` + `web_mouse_click` | the Tune tab's pad is inert; its one line says the PC needs an update. Nothing else on the tab changes |
| `web_bookmark_add` | append-only bookmarks | "Save this page" writes into SALU's own saved list and says where it went |

`proto` stays **1**. Every verb here is additive, and every fallback above is the behaviour
this section is replacing — which is exactly why the flags exist.

##### 17.14.6 Error codes added here

`no_web_mouse` — the pointer could not be moved or clicked (no injectable input, a locked
session). The phone's copy of `RemoteErrorCode` gets it in the same sitting as the PC's
(§17.13, A6.2 — the header comment on `lib/protocol/remote_protocol.dart` is the rule: two
copies, one meaning, changed together).

---

### 17.15 PC power from the phone's three-dot menu (2026-09-24)

The controls appear **only in the phone UI**: the existing ⋮ menu keeps Settings and
Forget this PC, then a divider, **Sleep PC** and **Shut down PC**. They are available
from any tab and Focus mode, not in the transport row and not in a collapsible card.
Both ask for confirmation, naming the connected PC; Shut down warns about unsaved work
and explains that the remote cannot turn the PC on again.

This is **not implemented on the PC in this repository** (`hamamun/salu-remote` is the
Android project). In `hamamun/Salu`, add the following authenticated commands to
`RemoteCommandHandler`; they act on Windows, not on SALU's media transport:

| Feature in `hello.features` | Verb | Args | Successful reply | Meaning |
|---|---|---|---|---|
| `pc_power` | `pc_sleep` | none | `ack` | Schedule Windows sleep. |
| `pc_power` | `pc_shutdown` | none | `ack` | Schedule a normal Windows shutdown (not a force-close, restart, or turn-on). |

Advertise **`pc_power` only if both commands are supported** on this PC. Keep
`proto: 1`: the verbs are additive; older PCs never advertise them and the phone
shows two disabled items, with an update hint when connected. When offline, the
items are disabled. The phone rechecks the link, feature and PC identity after
confirmation, sends a single command, and never automatically retries a power
request whose reply was lost.

The PC must apply its existing paired-device/LAN auth gate before either command.
The command handler should refuse further power requests while one is pending;
never run arbitrary shell input supplied by a phone. Check obvious Windows policy
or privilege failures and answer with an `error` and a readable message instead of
a false success. **Send the `ack` before performing the OS action** (schedule it
shortly afterward): if Windows suspends or exits within the handler, the socket
closes before the reply arrives and the phone cannot know whether it worked.
An `ack` means the request was accepted/scheduled, not that the OS has already
completed it. Do not force-close unsaved work on shutdown; Windows may delay or
veto it. The remote's existing reconnect loop resumes after sleep/wake. A powered-
off PC requires a person to turn it on; Wake-on-LAN is not part of this feature.

Acceptance: both verbs are rejected before auth, cannot be invoked on an old PC,
are issued exactly once after phone confirmation, and reply before the connection
is intentionally lost; verify sleep/wake reconnect and that shutdown does not
force-close an application with unsaved work. See `pc_part.md` Part D for the PC
implementation work order.

---

# Part 4 · APK interface design (§1 – §13)

> *(This Part was the whole of `remote_apk_ui.md`; its headings are one level deeper than they used to be, its section numbers are unchanged.)*

**Status:** 🎨 Design reference. The APK is a separate project, built later.
**Companion:** `remote.md` — the PC side. Its **§17** lists exactly what the PC must
add for everything described here.
**Supersedes:** the v1 layout of this file (5 screens) — the scope grew, so the
architecture changed. The rules and the visual language carried over unchanged.

---

### 1. What changed, and the one sentence that still decides everything

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

### 2. The new shape: three tabs, by intent

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

#### 2.1 What each mode offers (added 2026-09-20)

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

**The greying follows the snapshot in both directions, in the same frame as the body**
(fixed 2026-09-24). The bar has to *listen*; it must not read the mode while the page
happens to be rebuilding. It used to do the second, which made the greying a one-way
door: entering Web mode while Browse was up repainted the root (the §2.1 bounce calls
`setState`), so the seat greyed and looked right — but coming back to Player mode from
the Play tab repainted nothing else, so the seat stayed grey and kept answering *"the PC
is in Web mode"* to a PC that had already left it. `test/browse_seat_test.dart` pins both
directions and the sentence on tap.

The **mode switch shows both seats** — `Player` and `Web` side by side, not one
pill that toggles. You should be able to see where you are going before you go.

**Connect** stops being a screen most of the time: it is a **sheet** that slides up only
when a connection is missing or the user taps the header. First launch = the Connect
sheet; every launch after that = straight to Play, already connected.

---

### 3. The space system — how showing/hiding actually works

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

#### 3.1 PC power lives in ⋮, not on the Play screen (2026-09-24)

The existing three-dot menu stays available on **Play, Browse and Tune**, even
in Focus mode. It keeps **Settings** and **Forget this PC**, then a divider and
**Sleep PC** / **Shut down PC**. There is no Power card, no extra transport icon,
and no new PC on-screen button. Use explicit words: “Shut down PC” means turn
the computer off, not pause media or toggle its power.

The two items are visible but disabled when disconnected. When an authenticated
PC does not advertise `pc_power` they remain disabled with an update hint.
Tapping an enabled item names the PC in a confirmation dialog; sleep explains
the temporary disconnect/reconnect, shutdown warns about unsaved work and that
the phone cannot switch the PC back on. Cancel sends nothing. After confirmation,
recheck the link and PC identity before sending exactly one request. A reply
saying `ack` means “requested”, not proof that Windows has finished. If the
connection is lost before the reply, say so without automatically retrying a
potentially destructive command. Wire and PC requirements: `remote.md` §17.15.

---

### 4. Tab 1 — Play

#### 4.1 Player mode (the PC is playing)

```
┌──────────────────────────┐
│ ● Living Room PC  ⌄  ⋮  │ ← header: dot · name · focus · overflow
│  ◐ Player  ·  ◐ Web          │ ← MODE SWITCH (full width, 2026-09-26)
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

- **Mode switch** spans the full width above the title (user, 2026-09-26:
  *"make player and web toggle … look like repeat and shuffle"*): the same
  card container as the transport and repeat/shuffle rows, with the two seats
  splitting the row — `◐ Player` on one half, `◐ Web` on the other. It is still
  a *label and a switch* — it always shows the PC's real mode (the PC drives it),
  both seats stay visible, and tapping the unlit seat asks the PC to switch.
  When the PC switches on its own, the lit seat moves on its own. The old
  right-aligned compact pill is gone.
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

#### 4.2 Web mode (the PC is in its browser)

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

- **When no tab is open on the PC** (`web.tabs == 0`): the page card says *"No tab open"*
  without a URL; Back, Forward, Reload and Home are disabled; Fullscreen stays enabled
  (the PC window can still fullscreen); and the media play bar (seek, play/pause, volume)
  and any optimistic holds are immediately cleared.
- The transport rows **disappear** in both shapes instead of sitting there dead. Dead
  buttons are the fastest way to make an app feel broken.
- **Web-media controls drive the page's own player** (JavaScript on the PC side — see
  `remote.md` §17.11), not mpv. The volume slider is the site's own volume; it never
  touches the Windows volume. The bars are **live**, like the Play tab's own, and the
  numbers on the wire are the PC's — milliseconds and integer percent per `remote.md`
  §17.4, with the phone reading the units off the reply until the PC promises
  `web_media_unit`. A wrong unit here is invisible in every other control and total in
  these two, which is why the diagnostics sheet exists.
- **When the page's player cannot be reached or no media is found**: `web_media_get`
  answering `no_web_media` during poll clears media controls immediately back to the
  nav shape. A failed *control write* (`no_web_media` on a tap) shows one plain line —
  *"This site's player can't be controlled from outside."* — indicating cross-origin or
  DRM restrictions. Switching tabs, opening a new tab or closing a tab clears media
  and holds immediately so no previous tab's playback lingers.
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

### 5. Tab 2 — Browse

Segmented switch at the top: **Files | Streams**.

#### 5.1 Files — the PC's drives

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

#### 5.2 Streams — saved M3U URLs and a URL box

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

### 6. Tab 3 — Tune

Segmented: **Equalizer | Subtitles | Audio**. All three show *"Nothing is playing"* (with
a Play shortcut) when the PC has no media. **In Web mode none of the three exist** — mpv
is not in the picture — and the tab becomes a **mouse pad** instead (§6.0).

#### 6.0 Web mode — the tab becomes a mouse pad (rewritten 2026-09-24)

> **This replaces the D-pad.** The user, after using the D-pad on real sites: *"i need to
> remove this and everything. after removing it will be mouse pad as laptop has a nice
> bounding box will be shown which will be track pad. by touching there will activate mouse
> at salu and double tap will be enter. below track pad will be simple one line."*
> So the old D-pad is gone — no ◀▶ page navigation, OK, Esc chip, focus card, or extra
> explanation. The later up/down request adds only two ▲▼ seats under the pad, using the
> page's existing arrow keys; these are not a return of the D-pad. `web_key` stays in the
> protocol: double tap uses `Enter`, the seats use `ArrowUp` / `ArrowDown`, and `Escape`
> keeps its documented job on the PC.

In Web mode there is no equalizer, no subtitle track and no audio track to choose. What there
*is* is a web page the user cannot reach from the couch — so the tab hands them **the PC's own
pointer**, which is the thing that can reach everything on it.

```
┌────────────────────────────────┐
│                                │
│          the trackpad          │ ← 100% screen width, 60% screen height
│       (round-cornered box)     │   dynamic sizing, thin border (1.4 dp)
│                                │
└────────────────────────────────┘
              (▲)  (▼)            ← scroll the page: two 56 dp round seats
              Mouse                ← the one line, and nothing else
```

**Sizing and shape (dynamic):**
- **Width:** 100% of the screen width (`constraints.maxWidth`).
- **Height:** 60% of the phone's full screen height (`screenHeight * 0.60` —
  **was 70%** until the arrow row arrived, 2026-09-24), capped dynamically to
  the tab's available height minus the 18 dp pad-to-row gap, 56 dp arrow row,
  and 26 dp caption allowance. That room is subtracted **before** the clamp, so
  on a short screen the pad shrinks to make room for the arrows.
- **Corners and border:** Keeps rounded corners (`18 dp`) and a thin border (`1.4 dp`),
  maintaining the clean laptop-trackpad card appearance.
- **Arrow row:** two round seats, `56 dp`, `18 dp` apart, `18 dp` under the pad,
  in the pad's own gradient and hairline — part of the trackpad, not a toolbar.
- **Caption:** Preserves the one `"Mouse"` line right underneath the arrow row (and the
  PC update notice when `web_mouse` or `web_key` is unadvertised or answers `unknown_command`).

| Gesture | Does | Verb |
|---|---|---|
| drag | the PC's pointer follows the thumb, live | **`web_mouse_move {dx, dy}`** (new, `remote.md` §17.14.3) |
| single tap | left click, where the pointer already stands | **`web_mouse_click {button:"left", count:1}`** (new) |
| double tap | **Enter** — activate whatever the page has focused | `web_key {key:"Enter"}` (§17.13.5) — a double click when the PC has no `web_key` |
| **▲ / ▼** under the pad | **scroll the page** — the page's own arrow key, once per tap | `web_key {key:"ArrowUp"\|"ArrowDown"}` (§17.13.5) — greyed, never hidden, when the PC has no `web_key` |

**The scroll arrows, and what they honestly do** (user, 2026-09-24). They cost
nothing on the PC: the old D-pad's `ArrowUp`/`ArrowDown` stayed in the protocol
and stayed implemented when the D-pad was deleted — only their seat on the phone
went away. That is why they were reused rather than specified as a new verb, and
it is also their limit: on the PC these keys are a **focus walk** ("next
focusable element, `scrollIntoView`, `focus()`", §17.13.5), not a measured
scroll step. On an ordinary page that reads as scrolling, because the page keeps
the focused element centred; in a text field the arrows move the caret, and a
page with nothing focusable may do nothing. **One tap is one key, with no
hold-to-repeat on purpose** — repeated focus walks can race through the page's
focus order instead of giving the user a measured scroll step. A wheel verb
(`web_mouse_scroll`) is the right next step if this feels jumpy on real sites; it
is PC work, and this section is phone work.

**The one line under the arrow row says `Mouse`.** That is the whole text budget of this tab. The
only time it says anything else is the honest one: `web_mouse` and `web_key` are promised
separately in `hello.features`, so the line names whichever half is missing — *"Mouse needs
an updated SALU on the PC"*, *"Scroll needs an updated SALU on the PC"*, or both — still one
line, still the same box in the same place. A pad that silently does nothing is the one
outcome worth a sentence; everything else is noise in front of a page.


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
user still has the Play tab's own controls. The arrows are exactly as good as the site's own
markup (§17.13.5's honest limits, unchanged). Nothing is faked.

**Implementation.** `remote.md` §17.14.3; the phone side is `lib/ui/mouse_pad.dart`, and
`lib/ui/dpad.dart` is deleted.

#### 6.1 Equalizer

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

#### 6.2 Subtitles

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

#### 6.3 Audio

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

### 7. What the phone cannot know — and must be told

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

### 8. Feedback and latency rules, per feature

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

### 9. Marks to draw

The in-app UI ships **no image assets** for its controls — every control mark is a `CustomPainter`,
ported from the PC's `transport_marks.dart` / `salu_marks.dart` so both apps draw identical marks.
The Android launcher icon is the SALU logo from `hamamun/Salu` (`assets/images/salu_logo.png`).
New control marks needed for this scope (add them on the PC side first, then port):

`FolderMark` · `DriveMark` · `FileMediaMark` · `SubtitleMark (CC)` · `EqualizerMark` (exists) ·
`GlobeMark (web)` · `LinkMark` · `FullscreenMark` · `ChevronMark` · `SearchMark` ·
`ResetMark` · `QueueMark`

Same recipe: `markStrokeFor(size)` for the stroke, `markInk(context)` for the colour,
nothing filled, nothing boxed. At phone sizes the minimum stroke wants to be a touch
heavier (1.8–2.0) than at the PC's 18 px.

---

### 10. Build order (updated)

| Step | Deliverable | Notes |
|---|---|---|
| **A1** | Connect sheet → **Play** (transport, seek, volume) with the mode pill **and the playlist card** (5 rows, auto-scroll, tap-to-jump). | The proof. The card moved into A1 (user's answer #4) — `queue_get`/`queue_jump` are tiny reads the PC ships with R1. |
| **A2** | **Browse → Streams** (+ Add URL) and **Browse → Files** (read-only browser, pinned places, quick `▶`/`＋` marks). | Highest happiness per line of code in the whole app. |
| **A3** | **Tune → Subtitles** (tracks, sync, search, download) and **Tune → Audio**. | First feature that can genuinely save a ruined movie night. |
| **A4** | **Tune → Equalizer** + presets + Speed chips; **select mode** (checkboxes, select-all, bottom action bar) in Files. | EQ last, on purpose: it is the least-used tool in the set. |
| **A5** | Web mode body in both shapes (nav + web media + open-URL), Focus mode, Settings → Play screen, collapse memory, activity dot. | The polish pass that makes it feel like a finished product. |

Each step is usable on its own, and the app is never in a broken state between steps.

---

### 11. Deliberately not added (and the reason, so it is not re-litigated)

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

### 12. The advice I would give you before you build any of this

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

### 13. Open questions — all answered (2026-09-20)

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

---

# Part 5 · PC work orders for `hamamun/Salu` (Parts A – F)

> *(This Part was the whole of `pc_part.md`; its headings are one level deeper than they used to be, its section numbers are unchanged.)*

## Part F — large playlists, grouping parity and Web-mode stability (2026-09-26)

**Status: Remote implementation written in this branch; PC implementation pending.**
This work order supersedes Part B §11's `start + count` membership assumption
and Part E's claim that transport keepalive cannot be affected by a busy app.
Do not mark this complete until both apps pass the acceptance tests below.
No PC source has been modified in this Remote session.

### F0. What the Remote now does / rollout

- Shows queue pages progressively, requesting the now-playing channel's page
  first. Remaining pages load in the background; full search/favourites become
  complete as those pages arrive. This is progressive loading, **not yet an
  on-demand-only playlist**. The entire title list is eventually fetched.
- Shares one paced, serial read lane for row/group requests (100 ms gap after
  each response), leaving command-budget headroom for playback/heartbeats.
  Retries read-only `busy`, `too_fast`, `timeout` twice with backoff. Does not
  replay grouping mutations automatically.
- Reduces row/group page sizes on `too_large` (also recognizes the old PC's
  `busy` with the exact oversized-response explanation). Preserves successfully
  loaded pages on failure and offers Retry. Never increases the 8 KiB limit.
- Review follow-up: reloads clear obsolete group descriptors, progressive pages
  keep the playing row in view until manual scrolling/group selection, and
  malformed or duplicate membership fragments are rejected.
- Uses explicit membership indexes, preserves PC descriptor order, invalidates
  obsolete requests, and caches display construction across playback snapshots.
  Group changes follow authoritative snapshots; only one setting request at a
  time. Rows refresh when the **content revision** changes, even at the same size.
- **Compatibility:** new grouping reads require `hello.features` to include
  `queue_groups_paged` AND `state.queue.revision`. Without these, Remote shows
  a flat channel list and the short status “Grouped view unavailable on this
  PC version.” The chips can still change the PC setting via `queue_group_set`.
  It deliberately no longer asks for unbounded legacy `queue_groups` results or
  guesses members from `start/count`. Flat queues/playback keep working.
- Records the last ten socket-close diagnostics for this session, accessible in
  Connect → Connection history: timestamp, code, mode, authenticated state,
  connection age, snapshot age, pending command count, RTT, socket error type.
  No URLs, tokens, pairing codes or file paths are added to this history.
- Keeps the existing 10-second transport heartbeat unchanged pending evidence.
  Guards callbacks from obsolete sockets. Web media polling remains single-flight,
  skips inactive/offline states, and ignores responses from a prior page/link.
- Removes scattered instructional paragraphs in the Remote UI; labels, concise
  availability/error messages and destructive-action confirmations remain.

### F1. PC playlist panel must observe shared grouping state

Files: `lib/ui/panels/playlist_panel.dart`,
`lib/core/channel_view_service.dart`.

The panel currently observes queue/playback changes, but does not subscribe to
`ChannelViewService.groupMode` and `openGroup`. A Remote change therefore may not
paint until opening the panel triggers a rebuild.

1. Subscribe to both view notifiers; unsubscribe in dispose. Invalidate view
   descriptor/reveal caches and schedule a rebuild when either changes.
2. Batch/coalesce the mode and open-group notifications into one frame. Don't
   perform a whole-list regroup twice because `_queueGroupSet` sets both values.
3. Use one service-level mode-change operation for PC and Remote. Preserve the
   actual queue order and playing index; only the view changes. This operation
   must not depend on the panel being mounted/open.
4. Check PC pill, playlist list, playing-group reveal, search/favourites and
   grouped next/previous behaviour with the panel both open and closed.

### F2. Exact, byte-bounded grouping protocol — REQUIRED wire contract

Keep protocol version 1. Add the capability **only after all of F2 works**:

```
hello.features: [..., "queue_groups_paged"]
state.queue: {kind, count, index, grouping, revision: "opaque-content-token"}
```

`revision` is a non-empty string identifying the queue's content/order/metadata.
It changes for load, clear, replace, append, remove, reorder, metadata edits,
and a restarted PC session (avoid revision reuse after restart). It does **not**
change on position ticks, play/pause, current index, or grouping-mode choice.
Do not reuse the top-level snapshot `rev` here.

#### Rows (extension of existing command)

```
queue_get {from: 200, count: 100, revision: "token"}
→ {type:"queue_result", from:200, total:10000, revision:"token",
   rows:[{index:200,title:"..."}, ...]}
```

- Absolute queue indexes, ascending and consecutive; count means **maximum**.
- Byte-budget the complete encoded response including envelope/UTF-8 escaping.
  Return fewer rows if needed, not `busy`; Remote advances by actual row count.
- If one title is too large, safely shorten its display title; do not alter its
  playback identity/index. No URLs or private paths in Remote data.
- Provided revision not current → `stale_queue`, no mixed-version result.
- For old phones without a revision arg, retain the old request behaviour;
  additional response fields are harmless. Supplied valid revision is echoed.

#### Group membership pages (new read-only command)

```
queue_groups_page {by:"country", revision:"token", from:0, count:20}
→ {type:"queue_groups_result", revision:"token", by:"country",
   groups:[{key:"stable-key",name:"Bangladesh",count:240,start:3,
            indexes:[3,8,20,...]}], next:1}
```

Rules (must match `lib/core/queue_reader.dart`):

1. Precompute groups in PC descriptor-head order. Category: first appearance;
   country/language: alphabetical, Unknown last. **Never reorder the queue.**
2. Flatten the descriptors into a deterministic sequence of **fragments**.
   Split each group's actual index list into bounded non-empty fragments
   (suggest at most 100 indexes each; smaller if the encoded fragment needs it).
   Every fragment repeats that group's stable key, display name, total member
   count and first absolute member index (`start`). `indexes` is that fragment's
   exact membership, not a consecutive range. Fragments for a group are adjacent.
3. `from` is an offset into this fragment sequence, NOT a queue index or byte
   offset. `count` caps fragments (Remote starts at 20), NOT channel membership.
4. `next` must be explicitly present: `from + groups.length` if more fragments
   remain, otherwise null. Never a nonterminal empty page; never skip fragments.
5. Byte-pack whole fragments into <= 8192 bytes including the response envelope.
   Ensure even one fragment fits by constructing smaller fragments and bounded
   display labels/compact stable keys up front. Fragment boundaries must be
   deterministic for the same revision and mode, independent of requested count.
6. Multiple fragments with the same key must have identical name/count/start.
   Every queue channel belongs to exactly one group, including Unknown. No
   duplicate membership within or across fragments/groups; indexes are integers
   in [0, queue.count).
   The Remote merges fragments by key and validates final coverage/counts.
7. Evaluate the requested `by` independently of the current view setting.
   Valid modes here are category/country/language; invalid mode →
   `invalid_arguments`. Stale content revision → `stale_queue`.
8. A changed playlist while preparing a page must fail `stale_queue`, never send
   a page combining revisions. Response envelope must carry the command id and
   `ok:true` as with existing typed results, so the Remote correlates the reply.
9. Retain legacy `queue_groups` for old phones, but don't claim its range-based
   membership is correct for scattered channels. New Remote never calls it.

`start` remains descriptive/backward metadata only; it must not determine
membership. Example: A has [0,2], B has [1,3]; A is **not** [0,1].

#### Error semantics

- `busy`: temporarily unavailable, safe read retry.
- `too_fast`: rate budget reached, safe read backoff.
- `too_large`: cannot fit even the smallest response; never masquerade as busy
  or close a healthy socket. Normal pages should avoid this by byte-packing.
- `stale_queue`: supplied content token no longer current; Remote requests a
  state refresh and a changed revision triggers a new load.
- Keep generic request-size copy applicable to non-queue commands too.

Mirror any new protocol constants into both repos. Remote currently gates by
`RemoteFeature.queueGroupsPaged` and the new verb string and accepts these error codes without requiring a
protocol-version bump. Update `remote.md` in the PC repo to this exact contract.

### F3. Avoid repeated heavy work on the PC

Files: `remote_service.dart`, `remote_command_handler.dart`,
`channel_grouping.dart` and the panel/service view caches.

- Cache grouping availability and group membership by content revision and
  mode, shared between panel and Remote handler. Do not scan thousands of
  channels on every 120/250 ms playback snapshot or each requested page.
- Cache stable descriptors, not playback position. Invalidate only on relevant
  content/view changes; avoid sorting/filtering in frequent widget builds.
- Profile actual large M3Us. If parsing/group calculation blocks the UI isolate,
  move the pure data computation to a worker isolate; apply results only if the
  revision still matches. UI/WebView calls must stay on their supported thread.
- A Future timeout is not cancellation and cannot preempt synchronous blocking
  work. Timeouts alone are not a CPU isolation strategy.
- Treat the new group read as a quiet read: it must not restart browser polling
  or rebuild unrelated state. Heartbeats/playback controls bypass queue-read work.

### F4. Web-mode polling and disconnect diagnosis

Files: `remote_service.dart` (`_startWebMediaPolling`), browser service and
`remote_web_media_bridge.dart`.

1. The current 500 ms async periodic callback can overlap itself. Replace it
   with one outstanding browser script operation, completion-based scheduling,
   and bounded browser-operation handling. Restarting a Timer must not create a
   second outstanding operation. Skip polling with no authenticated phone, no
   live tab, or outside Web mode.
2. Associate results with browser/tab identity + a generation. Ignore results
   after navigation, close, mode switch or shutdown. Include exceptions/finally
   cleanup so one failed script cannot silently disable polling forever.
3. A Dart timeout does NOT cancel an underlying WebView script. Do not clear an
   in-flight guard on timeout and immediately submit more scripts to the same
   stalled controller. Reuse a single guarded media-read service for PC polling
   and Remote `web_media_get` where possible; use supported controller recovery
   or wait for the original operation to settle.
4. Keep application ping replies outside expensive command handling. Transport
   pings still depend on runnable event loops; investigate a separate network
   isolate only if profiling proves shared-isolate starvation. Do not assume
   moving a switch-case makes the socket immune to stalls.
5. Log socket-close code/reason, timestamp, last valid frame/snapshot/heartbeat,
   event-loop lag, pending browser operations and command durations on the PC.
   Avoid URLs/tokens/codes/private paths. Pair these with Remote connection
   history. Code 1001 alone does not prove Wi-Fi failure or heartbeat expiry.
6. After evidence, consider a measured heartbeat tolerance adjustment on both
   ends. Do not disable keepalive or simply raise every timeout. Preserve real
   Wi-Fi-loss detection, pairing semantics and reconnect backoff.

### F5. Acceptance / regression checklist

- Open PC panel; change grouping on Remote: list and pill update without reopen.
  Repeat with panel closed then reopened, and PC → Remote in all modes.
- Alternating countries/languages/categories: exact members and PC descriptor
  order agree; selected channel/group and next/previous remain correct.
- 10,000 and 50,000 channels, thousands of group heads, very long Unicode names,
  one enormous group: every encoded frame <= 8192 bytes; no oversized busy or
  connection closure; first row page paints before the final page arrives.
- Explicit fragments split a group over pages; cursor is monotonic and bounded;
  no omitted/duplicated channels. Shared read budget leaves controls responsive.
- Change mode rapidly while loading; replace playlist with another of the same
  length; clear mid-read; reconnect; navigate away. No old rows/groups overwrite
  newer state. Retry is bounded and previously displayed valid data survives a
  transient read failure. On old PCs, safe flat fallback—not guessed groups.
- Delay/reject browser script execution; navigate/close tabs during requests.
  At most one underlying media probe at a time, stale results ignored, no
  unhandled async exception. Web mode must remain controllable under load.
- Run Web playback + large M3U + Remote gestures for at least 30 minutes;
  Wi-Fi off/on, phone background/foreground, PC sleep/wake. Inspect both logs,
  distinguishing true disconnects from command failures before claiming fixed.
- Run Flutter analyze and all tests in both repos. Added Remote regression tests
  are `test/queue_reader_test.dart` plus updated `test/queue_view_test.dart`.
  This sandbox could clone Flutter but SDK downloads failed (TLS/network), so
  Flutter compilation/tests could not be executed here; do not treat written
  tests or a syntax-only check as a passing Flutter build.

---

## PC part — work orders for the Salu repo

> **Where this applies:** the PC app repository `hamamun/Salu` (Flutter Windows 10/11
> player). The phone repository `hamamun/salu-remote` is already updated for everything
> written here — the code is written and the tests are written, and every door degrades
> politely wherever the PC has not caught up yet. One caveat, stated plainly in A10: the
> sandbox the phone side was written in has **no Flutter SDK**, so `flutter analyze` and
> `flutter test` have not been run on it yet. Do that first.

Five work orders live in this file:

| Part | Date | What | Status |
|---|---|---|---|
| **E** | 2026-09-24 | **Connection reliability** — keep the phone's link honest: `ping` answered on the socket path, `state_get` snappy under load, connection bookkeeping, spec-row cleanup | **built in this repo (see Part E implementation) — acceptance on the user's PC pending** |
| **D** | 2026-09-24 | **PC power** — authenticated `pc_sleep` / `pc_shutdown`, both advertised by `pc_power` | **built in this repo (see Part D implementation) — acceptance on the user's PC pending** |
| **C** | 2026-09-24 | **The web fixes the user reported after using it** — one fullscreen seat that actually works (`web_fullscreen` + the gesture problem), Home, the trackpad (`web_mouse_move` / `web_mouse_click`), add-only bookmarks, and the blank new tab | **built in this repo (see the Part C implementation record) — acceptance on the user's PC pending** |
| **A** | 2026-09-23 | **The web section** — page-player units (the reported bug), the right media element, `web_key` + the focus ring, the tab strip mirror (list · switch · close · new), the bookmark mirror | live; still needed (C builds on it) |
| **B** | 2026-09-22 | The `fs_places` drive scan (§1–9), the group-by pill bug (§10), channel grouping (§11), phone-local channel favourites (§12, a record, no PC work) | unchanged, kept below |

The protocol for Part A is already written into the phone repo's `remote.md` — **§17.4**
(verbs and units), **§17.11** (the web-media bridge) and **§17.13** (tabs, bookmarks,
focus, feature flags). The phone-side UI spec is `remote_apk_ui.md` §4.2, §6.0 and §8.
Read §17.13 once before starting: it is the contract, and this part is the shopping list.
Part C's contract is **§17.14**, and its shopping list is Part C below.
Part D's contract is **§17.15**; it is independent of the web work.

**Part C and Part A are not alternatives.** A3–A5 (the focus keys, the tab mirror, the
bookmark mirror) are what Part C's new verbs lean on: `web_fullscreen` clicks the page's own
fullscreen control, `web_mouse_click` clicks wherever the pointer is, and `web_bookmark_add`
needs the bookmark store A5 already reads. Do A first if it is not in yet; C then needs no
rework.

---

## Part E — connection reliability: keep the phone linked (2026-09-26)

> **Why this exists — the user's words:** *"the remote frequently lost connection with the
> PC and reconnecting, causing lagging of real time update at remote and synchronization
> problem with PC Salu."* A full audit of this repo (`lib/core/client.dart`,
> `lib/ui/root.dart`, the three poller panes, `AndroidManifest.xml`, `pubspec.yaml`)
> found the phone carried most of the blame and has already been rebuilt for it (E0).
> What remains for `hamamun/Salu` is small but **non-optional**: the PC must answer the
> two things the phone now deliberately leans on — a **busy-proof keepalive** and a
> **prompt `state_get`** — and must keep its connection bookkeeping honest.
>
> **No protocol change.** Same wire format, same `proto: 1`, no new verbs, no feature
> flags, no version gate, no bump. This part is timing and isolation rules only.

### E0. What the phone already changed (context — no PC work)

Recorded so the PC side knows exactly what it can now rely on:

1. **Death of a link is declared only by the transport** — Dart's socket-level
   `pingInterval` (now 10 s), the close event, and Android's network-change feed.
   The app-level `ping` command is a **speedometer for the Connect sheet and nothing
   else**; the old rule ("no app-level `pong` for 12 s ⇒ tear the socket down") is
   gone. A busy PC can no longer look like a dead network from the phone's side.
2. **A transient drop keeps the last snapshot on screen** — no Connect-sheet flash,
   no forced jump to the Play tab; `hello`'s embedded snapshot repaints on reconnect
   (force-applied, so even a PC that restarted its `rev` counter wins over the kept
   picture).
3. **Faster, honest recovery** — single in-flight dial (no ghost sockets stacking
   against the PC's max-4 budget), resume does a real 3 s `state_get` health check
   and redials immediately on failure, network-up events redial at once with a fresh
   backoff budget, the backoff counter only resets after a real `auth_ok`, and stale
   teardown callbacks can no longer clobber a fresh connection (generation checks).
4. **Stall nudge** — while the snapshot says `playing` and snapshots go quiet for
   4 s, the phone sends one `state_get` (4 s budget) instead of freezing under a
   green dot. This is `remote.md` §6.3's *"detect a stalled link"* made real, and it
   **depends on E3 being true**.
5. **Sync hole closed** — absolute commands (`seek_to`, `set_volume`, `queue_jump`,
   `eq_set`, `sub_delay`, …) that fail while the link is down are parked for one
   replay within 20 s of the next `auth_ok`; toggles are never replayed. A failed
   socket write is reported as *offline* (never as "too big") and rebuilds the
   connection immediately. The Tune-tab panes stop polling while offline and refresh
   the moment the link returns.

### E1. Answer `ping` on the socket path — `lib/core/remote/remote_service.dart`

* **Rule:** the `ping` verb (`remote.md` §9) must be answered with its `pong`
  **inline, on the WebSocket's own isolate/event loop**, the moment the frame
  arrives. It must **never** be enqueued behind the command isolate, never wait
  behind a queue of `fs_open` / `web_mouse_move` / `subs_download`, and never share
  the 3-second handler guard's waiting line.
* **Why now:** the phone's own audit proved this class of stall is real on the
  user's machine — Part B documented the `fs_places` scan blocking *the command
  isolate for 10–30 s per dead drive letter* with an "endless timeout → retry →
  busy loop". If `ping` rides that pipeline, a stall that long used to masquerade
  as a dead link at the far end. The phone no longer kills on a late `pong`, but a
  prompt `pong` is still what keeps the Connect sheet's latency number honest.
* **Shape (unchanged):** `{"type":"pong","proto":1,"at":<echo>,"serverAt":<now>}` —
  echo the phone's `at` exactly; the phone computes RTT from it.

### E2. Socket I/O stays on the main isolate — `remote_service.dart` / architecture check

* Verify — and if needed, correct — that **all WebSocket frame reads/writes and
  dart:io's automatic protocol-level pong run on the main isolate**, while heavy
  work (filesystem, injections, OS calls) stays on the command isolate exactly as
  Part B/A already demand. The phone's *transport* keepalive (`pingInterval = 10 s`)
  depends on dart:io's pongs being able to leave while the command isolate is
  blocked; that is only true while socket I/O is not itself parked on the busy
  isolate.
* Do **not** move `remote_command_handler` work onto the main isolate to "fix" a
  busy pong — that re-creates Part B's hang at a larger scale. The correct split is:
  socket layer (main) / commands (command isolate) / `ping` answered at the socket
  layer per E1.

### E3. `state_get` stays prompt under load — `remote_command_handler.dart`

* The phone's stall nudge gives `state_get` **4 seconds** (and its resume health
  check **3 seconds**). The existing 3-second handler guard already fits — verify
  it **cannot be starved**: `state_get` must not sit behind a long `fs_open` scan
  or a burst of trackpad moves in a way that pushes its answer past ~3 s.
* Cheap correct answer beats a late perfect one: if the builder is mid-burst, the
  120 ms event clock (`remote.md` §7.2) still flushes one snapshot; `state_get`
  should trigger that flush and ack even when nothing changed (`ack` with no body
  is fine — the phone only needs *an* answer, plus any pending snapshot).

### E4. Connection bookkeeping — `remote_service.dart`

* **Auth timeout:** keep the 5 s connect→`auth` reap (`remote.md` §7.1.6) — the
  phone's dial-guard (E0.3) means fewer ghosts, but the reap is still the backstop.
* **4005 (max 4):** count only sockets that are actually alive. Free a device's
  slot the instant its socket closes/errors (`onDone`/`onError`), not at the next
  ping tick — the phone reconnects quickly now and must not be refused by a slot
  that is already dead.
* **`socket.pingInterval = 20 s` on the server** (spec §11): keep it; it is the
  PC's own reap of a vanished phone, independent of anything above.

### E5. Fresh-socket snapshot and `rev` — verify only

* `remote.md` §6.1/§7.2 already promise: *new socket = full snapshot immediately,
  `hello` carries a full snapshot, `rev` monotonic per process run.* Verify both
  still hold after any refactor. The phone now force-applies the `hello` snapshot,
  so a PC process restart (rev reset) is also safe — no PC change needed, but do
  not "optimize" the fresh-socket snapshot away; the reconnect paint depends on it.

### E6. Spec rows to fix in `remote.md` (same sitting as the code)

* **§9 `ping` row** — extend the reply column's meaning: *latency display only;
  a late `pong` never means the link is dead (transport keepalive owns death);
  `ping` is answered inline on the socket path (Part E1), never queued behind
  the command isolate.*
* **§7.2 or §11** — one line: *link death is declared by transport-level
  keepalive and close events; command-path delays (busy, `too_fast`, long
  scans) are not evidence of a dead link and must not be treated as such by
  either side.*
* Leave the frame shapes, close codes, and `proto` untouched.

### E7. Tests to add on the PC side

1. **`ping` while the command isolate is blocked:** start a fake handler that
   sleeps past the 3 s guard (or directly blocks the command queue), send `ping`
   on an authenticated socket, assert a `pong` arrives well inside 1 s with the
   echoed `at`.
2. **`state_get` under a mouse-move burst:** 25 `web_mouse_move`/s in flight →
   `state_get` still acks ≤ 3 s and a snapshot flush follows.
3. **Slot accounting:** open and abruptly kill 4 sockets in sequence; a 5th
   connect after each kill must never see `4005` from a corpse slot; the real
   max of 4 *live* sockets still answers `4005`.
4. **Fresh-socket snapshot:** every accepted socket receives `hello` (with state)
   and/or an immediate snapshot before any unrelated push — unchanged from §6.1.

### E8. Acceptance checklist (verify on the user's PC, in this order)

1. With a folder scan or other known slow command running, watch the phone's
   Connect sheet: latency shows a number (even a large one) — **no "Reconnecting…"
   cycle** while the PC is merely busy.
2. While a video plays, throttle the PC (or block the command isolate briefly):
   the phone's UI stays on the last picture and recovers within ~one nudge
   (`state_get` round trip) once the PC is responsive — no blank screen, no
   Connect sheet.
3. Toggle the phone's Wi-Fi off and on: reconnect happens the moment Wi-Fi is
   back (E0.3), first frame correct from `hello`, no re-pairing, and no `4005`.
4. Sleep and wake the PC: the phone's socket dies via keepalive, reconnects on
   the PC's return, and paints in the first frame — same as §11's promise.
5. Leave the link idle 10 minutes: zero reconnect cycles in the phone's log
   (`[SALU remote]` lines), latency still updating once per ping.

---

## Part D — sleep and shut down from the remote's ⋮ menu (2026-09-24)

> The **phone-side work is in `hamamun/salu-remote`**, not in the PC repo:
> `lib/ui/root.dart` (two menu items and confirmation), `lib/core/client.dart`
> (wire verbs), `lib/core/models.dart` (feature gate), and the power tests.
> Neither item can actually sleep or shut down a PC until this part is built in
> `hamamun/Salu`. The exact contract is `remote.md` §17.15.

1. In **`lib/core/remote/remote_command_handler.dart`**, accept `pc_sleep` and
   `pc_shutdown` only after the server's normal LAN and paired-device auth gate.
   They have **no arguments** and must not route through media transport. Reject
   a second power request while the first is pending; never accept an arbitrary
   executable/command line from the phone. Do not add on-screen power controls
   to the PC app — only the remote UI has the buttons.
2. Use a small **Windows power service** for the actual system operations:
   suspend for `pc_sleep`, normal shutdown for `pc_shutdown`. Respect Windows
   policy/privilege errors and unsaved-work prompts; **do not force-close apps**.
   An OS refusal should produce an `error` with a readable explanation when
   known before scheduling. Do not confuse shutting down SALU with shutting down
   Windows, and do not add Wake-on-LAN or a turn-on verb.
3. In **`lib/core/remote/remote_service.dart`**, send the command's `ack`
   **before** dispatching the OS action after a short delay. Running sleep or
   shutdown inline closes the WebSocket before the phone receives the reply.
   `ack` means accepted/scheduled, not proof Windows finished the operation.
   Advertise `pc_power` in `hello.features` **only once both verbs work** on
   the current system; keep `proto` at 1. The phone shows disabled menu items
   while offline or when the feature is absent.
4. Test with an injected/fake OS power service (never sleep or shut down a CI
   runner): unauthenticated/unsupported requests fail, a paired phone's single
   request is acknowledged before dispatch, duplicates cannot launch a second
   system call, failures are reported honestly, and both verbs work in Player
   and Web modes. On a real Windows PC, confirm sleep/wake reconnect and verify
   that shutdown does not force-close unsaved work.

---

## Part C — the web fixes the user reported after using it (2026-09-24)

> Phone side: **already built** in `hamamun/salu-remote` (`lib/ui/web_body.dart`,
> `lib/ui/web_tabs_card.dart`, `lib/ui/mouse_pad.dart`, `lib/ui/web_sheets.dart`,
> `lib/core/web_url.dart`, `lib/core/client.dart`, `lib/core/models.dart`). Every piece below
> degrades to the phone's current behaviour while the PC has not caught up, so this part can
> land in any order — but the order written here is the order the user will feel it in.
>
> Contract: `remote.md` **§17.14**. This file is the shopping list.

### C0. What the user reported, in their words

| # | Complaint | Where it lives |
|---|---|---|
| 1 | *"fullscreen button making salu fullscreen for other video stream except youtube which is not getting fullscreen"* | **PC** (C1) — one seat must try the page's player first, and the injected fullscreen call needs a real gesture |
| 2 | *"at previous page icon place home icon which bring current loaded page to its homepage as salu do"* | **PC** (C2) + phone (built) |
| 3 | *"open tab … below volume bar … heading 'open tab' … collapse/expand like queue"* | phone only (built — `web_tabs_card.dart`) |
| 4 | *"when i am typing url then press open tab its opening blank tab"* | phone (built — `web_url.dart` adds the scheme) **and PC** (C5 — `web_tab_new` must navigate inside the new tab) |
| 5 | *"web saved pages … also showing m3u list from player section … only bookmark should show"* | phone only (built — the sheet lists bookmarks alone) |
| 6 | Tune tab, Web mode: the D-pad out, a laptop-style **trackpad** in — *"by touching there will activate mouse at salu and double tap will be enter"* | **PC** (C3) + phone (built — `mouse_pad.dart`) |
| 7 | Tune tab, Web mode: *"reduce the mouse pad height to 60 % and below that … add a scroll button or up/down arrow button that will work as keyboard up/down arrow"* | **phone only (built)** — `mouse_pad.dart`: 70% → 60%, plus ▲▼ seats on the existing `web_key` arrows — see the note at the end of C3 |

Everything the phone needed for 3, 5 and half of 4 is done and testable today. 1, 2, 3's tail
(`web_tabs_get`), 4's tail, 6 and the bookmark half of 5 need code in `hamamun/Salu`.

### C1. One fullscreen seat that actually works — `web_fullscreen`

**Read `remote.md` §17.14.1 first.** The short version: the phone now sends **one** verb and
the PC picks the target, in this order.

**File: `lib/core/remote/remote_web_media_bridge.dart`** (the §17.11 bridge) gains a
fullscreen **plan**, not just a script injection:

1. **Try the element.** If the §17.11 find-script found a player, request fullscreen on its
   container (`el.requestFullscreen?.() ?? el.webkitRequestFullscreen?.()`, wrapped in the
   house try/catch), then **read back** whether it took: `document.fullscreenElement` (or
   `document.webkitFullscreenElement`) plus `el.webkitDisplayingFullscreen`. WebView2 will
   refuse a `requestFullscreen()` with no user activation, and a refusal is silent — the
   read-back is the only way to know.
2. **If it did not take, use a real input click.** Ask the page for the *player's own*
   fullscreen control — the standard order: `[aria-label*="fullscreen" i]`,
   `.fullscreen-button`, `button[title*="fullscreen" i]`, `video::-webkit-media-controls-fullscreen-button`'s
   owner if it is reachable, and finally the largest visible button inside the player
   container — return its `getBoundingClientRect()`, convert to screen coordinates, and fire a
   **real** click through the PC's simulated-input path at that point. **This is the fix for
   YouTube**: a real click *is* user activation, so YouTube's own button does what the
   injected call could not.
3. **If the page has no reachable player** (the find-script says `found:false`, or it is a
   cross-origin iframe), fall back to `WindowStateService.instance.toggleFullscreen()` and
   report `target:"window"`. That is today's behaviour — kept, but only as the *last* choice,
   never instead of trying the page's player.
4. **`on:false` always leaves**: exit element fullscreen if it is on, then the window's. A
   seat that cannot un-fullscreen is worse than one that cannot fullscreen.

**File: `lib/ui/browser/…` (wherever the WebView2 host lives).** `ContainsFullScreenElement`
is the host's duty: when it becomes true, SALU must make its window fill the screen itself;
when it becomes false, it must put the window back. A page that enters fullscreen while the
host does nothing *looks exactly like the bug the user reported*. Bind the event, drive the
window from it, and let Esc (the phone's `web_key {key:"Escape"}` and the PC's own key) leave
the way it already does.

**Handlers.** `remote_command_handler.dart` gains `web_fullscreen`:

```
web_fullscreen  {on?}  →  ack {fullscreen: <bool>, target: "page" | "window"}
```

**`web_media_get`** gains `fullscreen: <bool>` — the element's state **now** (the phone's mark
reads it so the icon is never a guess). `canFull` keeps meaning *possible*.

Then **advertise `web_fullscreen`** in `hello.features`.

### C2. Home — `browser_nav {action:"home"}`

`browser_nav` already routes through the bridge the screen installs (§17.7). Add the action:

- **What it does:** SALU's own home page if the browser has one configured; otherwise the
  **origin of the active tab's URL**, loaded **in that same tab** (`https://www.youtube.com/watch?v=…`
  → `https://www.youtube.com`). Same tab matters — this is the button that takes a video page
  back to the site's front page, not a second window.
- **Nothing to go home to** (`about:blank`, a `file://` page): `ack`, no navigation. Not an
  error, and no error code for it.
- **Unknown action** keeps answering `invalid_arguments` (the phone then falls back to
  `browser_open` with the origin it computes itself — the seat still works on this PC, maybe
  with a new tab).
- **Advertise `web_home`** when it is implemented.

### C3. The trackpad — `web_mouse_move` / `web_mouse_click`

The phone's Tune tab is now a trackpad, two scroll seats and one line
(`mouse_pad.dart`). It sends, and expects
the PC to obey:

| Verb | Args | Meaning |
|---|---|---|
| `web_mouse_move` | `{dx, dy}` | move the **PC's own pointer** by exactly this much, relative, in CSS pixels at the WebView's scale |
| `web_mouse_click` | `{button:"left"\|"right"\|"middle", count:1\|2}` | a real click at the pointer's current position |

**Implementation, new file `lib/core/remote/remote_input_service.dart`:**

1. **Absolute mouse events are not an option.** `SendInput` (or `mouse_event` where SendInput
   is unavailable) with `MOUSEEVENTF_MOVE` **without** `MOUSEEVENTF_ABSOLUTE`, so the PC's
   normal cursor acceleration is applied the way the user expects for a real mouse. The phone
   has already applied its own gain (2.5×) and clamped each packet to ±320 px — **do not add
   acceleration of your own on top**; two gains is a pointer that overshoots everything.
2. **Clicks are real clicks** at wherever the pointer stands (`MOUSEEVENTF_LEFTDOWN` +
   `LEFTUP`, `count` times with the system's double-click interval between). Injecting
   `element.click()` in the page is *not* an implementation of this verb: the entire point of
   a pointer is that it works on canvas players, video overlays and DOM buttons alike.
3. **Non-blocking by construction.** 25 of these arrive per second while a thumb moves. The
   handler must move the pointer and ack; it must never await anything page-side.
4. **`no_web_mouse`** when the pointer genuinely cannot be delivered (no injectable input, a
   locked session). **Advertise `web_mouse`** only when both verbs work — a flag that answers
   `unknown_command` puts a sentence under the user's trackpad.

**Pointer visibility.** In fullscreen the Windows cursor hides itself; a trackpad with no
visible pointer is unusable. While a phone is connected in Web mode and the pad is in use,
make sure SALU shows its cursor over the WebView (the PC already has the machinery —
`SettingsService`'s `mouseOverPreview` and the OSC's own cursor handling are the neighbours to
look at). This is part of C3, not a nicety: it is the only feedback the user gets.

**Rate.** Movement is ~25 cmd/s; the per-device budget is 30/s (§6.2) and the phone's own
web-media poll is 1/s. Leave the budget alone rather than raising it — the phone's batching is
what keeps this inside it.

**No PC work for the scroll arrows (2026-09-24).** The phone's Tune tab now also has two
scroll seats under the pad, and they send `web_key {key:"ArrowUp"|"ArrowDown"}` — the D-pad's
old keys, already specified (§17.13.5) and already implemented by A3. Nothing here changes:
no new verb, no new flag, no new error. The only thing to check on the PC is that
`web_key` really is in `hello.features` (A6), because a build that omits it gets greyed seats
and the phone names the missing feature(s) in its one-line caption.

If these seats turn out to feel jumpy on real sites — remember they walk focus rather than
scrolling a measured step — the answer is a wheel verb, and it belongs here beside the rest of
the input path: `web_mouse_scroll {dy}` as `SendInput` + `MOUSEEVENTF_WHEEL` in
`remote_input_service.dart` (120 = one detent, same ±clamp and same non-blocking rule as the
moves), advertised as `web_scroll`. Not built, not ordered — noted so the next request does
not have to rediscover where it goes.

### C4. Add-only bookmarks — `web_bookmark_add`

☆ Saved pages is bookmarks only now, so **Save this page** has to land in that list to be
worth anything.

```
web_bookmark_add  {url, name?}  →  ack   (errors: no_web_bookmarks, invalid_arguments)
```

- **Append only.** No rename, no delete, no reorder, no sync. A URL already in the store is a
  no-op, not a duplicate (§17.13.4's rule is unchanged — it is about *rewriting*, and this verb
  cannot rewrite anything).
- Write where A5 already reads: the browser's own bookmark store, at the top level (`folder`
  stays empty for phone-added entries).
- If the browser has no bookmark store, do not advertise `web_bookmark_add` and do not
  advertise `web_bookmarks`; the phone then saves into SALU's list and says so in its snackbar.
- **Advertise `web_bookmark_add`** when it is implemented.

### C5. The blank new tab — `web_tab_new {url}`

The phone now sends a scheme with every typed address (`web_url.dart`: "youtube.com" →
"https://youtube.com"), which removes the most common cause. The remaining one is the PC's:

- `web_tab_new {url}` must **create the tab and navigate it**, not create an empty one and
  hope. The order that works with the existing strip: the screen's own add-tab (so the strip,
  the session and the handlers all see it) → set the new tab's URL → make it active → `ack
  {index}`. If the URL cannot be loaded at all, answer `invalid_arguments` rather than leaving
  the user on a blank page.
- A URL with no scheme that still slips through (a third-party client, a paste from somewhere
  odd) should be treated the way SALU's own Open-URL modal treats it — that modal already
  knows.

### C6. Housekeeping, tests, and the phone-side file list

1. **`hello.features`** gains, truthfully and only when implemented: `web_home`,
   `web_fullscreen`, `web_mouse`, `web_bookmark_add`. `proto` stays **1**.
2. **`RemoteErrorCode`** gains `no_web_mouse`. Mirror it into
   `salu-remote/lib/protocol/remote_protocol.dart` in the same sitting — the two copies are
   one file with two addresses, and the phone's user-facing copy for it already exists
   (`lib/core/error_copy.dart`).
3. **The phone's spec copy is already updated**: `remote.md` §17.4 (the verb tables),
   §17.5 (`web_media_get`'s `fullscreen`), §17.13 (the superseded-in-part note) and the new
   **§17.14**. `remote_apk_ui.md` §4.2 and §6.0 follow the new shapes.
4. **Files touched on the phone side** (for anyone reading a diff across both repos):
   `lib/core/web_url.dart` (**new**), `lib/ui/web_tabs_card.dart` (**new**),
   `lib/ui/mouse_pad.dart` (**new**, replacing `lib/ui/dpad.dart`, which is deleted),
   `lib/ui/web_body.dart`, `lib/ui/web_sheets.dart`, `lib/ui/tune_tab.dart`,
   `lib/core/client.dart`, `lib/core/models.dart`, `lib/core/error_copy.dart`,
   `test/web_url_test.dart` (**new**), `test/web_media_test.dart`.
5. **PC-side tests to add** (`test/remote_web_fullscreen_test.dart`,
   `test/remote_mouse_test.dart`, `test/remote_bookmarks_test.dart`):
   - fullscreen: target selection (player present → `page`; absent → `window`);
     `requestFullscreen` refused → the real-input fallback is used; `on:false` leaves both;
     the ack's `target` matches what actually happened; `web_media_get` reports `fullscreen`.
   - mouse: relative movement math (a `dx`/`dy` pair moves the pointer by that much, twice in
     a row adds up); click count 1 vs 2; a `middle`/`right` button; `no_web_mouse` when the
     injector is unavailable; the handler never awaits page-side work.
   - bookmarks: append adds one entry; the same URL twice adds one; nothing else in the store
     changes; an unadvertised PC answers `unknown_command` for the verb (which is what the
     phone's fallback tests against).
6. **Acceptance, on the user's own PC, in this order** (this is the list to hand to them):
   1. YouTube video → press fullscreen on the phone → **the video fills the screen** (not the
      bare app window), and the icon becomes the exit mark. Press again → it leaves.
   2. A site with no player → press fullscreen → the SALU window goes fullscreen, exactly once,
      and the icon follows.
   3. A YouTube video page → press **Home** → youtube.com's front page, same tab.
   4. Tune → the pad: drag → the PC's cursor moves; tap → a click; double tap → Enter. No text
      on the tab but the one line under the pad.
   5. Web → Saved pages → **only** the browser's bookmarks (no m3u rows). Save this page →
      it appears in that list within a second (or the snackbar says it went to SALU's list).
   6. New tab → type `youtube.com` (no scheme) → Open → the page loads in the new tab.
   7. Play → Open tabs section: collapse, expand, switch, close, ＋ — and the state survives a
      screen change (it is remembered like the queue's).

### Part C — implementation record (2026-09-24)

Done in this repo. Every item below is PC-side; the phone side was already built.

| C | Package | Where it landed |
|---|---|---|
| C1 | `web_fullscreen` — one seat, the PC picks | `remote_web_media_bridge.dart`: `RemoteWebMediaScripts.fullscreenPlan()` (find the programme element → already fullscreen? → injected `requestFullscreen()` on the player container → locate the player's **own** control: `.ytp-fullscreen-button`, `aria-label`/`title` containing *fullscreen* **or** *full screen* (YouTube spells it with a space), video.js / JW / Plyr classes, then the rightmost button in the bottom-right strip of the player; a label containing *exit* is never picked; answers the centre in device pixels of the view), `fullscreenState` (read-back), `exitFullscreen`; and `RemoteWebFullscreen`, the plan itself: read-back after the injected call → a **real click** on the control → read-back → the SALU window only when the page has no reachable player (or refused everything — the ack then says `window`, truthfully). `on:false` leaves the element first, then the window. `web_media_get` gains `fullscreen` (the document's reading OR the host's `pageFullscreen`). |
| C1 | the real click | `third_party/webview_windows` **Delta 3** (Dart only): `WebviewController.sendMouseClick(Offset)` — the view's virtual cursor moves to the control, 120 ms settle (hover-revealed controls come on stage), then press/release through `ICoreWebView2CompositionController::SendMouseInput`. That is *the same* input path the physical mouse over the view uses, so the page sees trusted input with user activation. `browser_screen.dart` installs it per active tab via `BrowserService.setRemotePageHandlers` (device px ÷ the view's DPR = the widget's logical px, the scale the `Webview` widget hands the engine). |
| C1 | the host cooperates | Already true before Part C: `WebTab` binds `containsFullScreenElementChanged` → `wantsFullscreen` → `BrowserService.setWebFullscreen` → the window fills the screen / comes back, and Esc leaves the way it did. Nothing to add; `RemoteWebFullscreen` reads that same `pageFullscreen` truth. |
| C2 | Home | `browser_nav {action:"home"}` → `BrowserService.navActions` / `RemoteBrowserBridge` / the handler all accept `home`; the screen answers it with **its own `_goHome()`** (no second code path): a loaded page goes to `WebAddress.homeUrl` (its origin) in the same tab; a page with no website home keeps/returns to SALU's start page, exactly as the on-screen button does. Unknown actions still answer `invalid_arguments`. |
| C3 | the trackpad | **New** `lib/core/remote/remote_input_service.dart`: `SendInput` with `MOUSEEVENTF_MOVE` (relative, never absolute), CSS px × the window's device-pixel ratio, ±320 px clamp re-applied at the edge, sub-pixel remainder carried per axis (two moves add up exactly), **no gain of its own**; clicks are `DOWN/UP × count` in one `SendInput` batch (Windows reads count 2 as a double click). A short `SendInput` return (locked desktop, UIPI) → `no_web_mouse`. Pure synchronous calls — the handler never awaits anything. `RemoteService` no longer restarts the 500 ms media poll or dirties the snapshot for `web_mouse_*` (at 25 moves/s the poll would otherwise never fire). **Pointer visibility:** SALU never hides the cursor over the browser, and because the moves are genuine OS input the page receives real `mousemove`s, so a player that hid its cursor in fullscreen shows it again — no extra switch was needed. |
| C4 | add-only bookmarks | `web_bookmark_add {url, name?}` appends to `WebFavouritesService` (the store `web_bookmarks_get` mirrors), top level. The address is resolved the omnibox way (`youtube.com` → `https://youtube.com`); non-URLs answer `invalid_arguments`; the same page (canonical match) twice is a no-op that acks the existing entry. The store has **15 seats** (`maxEntries`) — a full store answers `no_web_bookmarks` so the phone falls back to SALU's list and says so. The ack carries `{entry:{name,url,folder}}`. |
| C5 | the blank new tab | `browser_screen.dart`'s tab handler resolves `web_tab_new {url}` with `WebAddress.urlFrom` before `_newTab` (a bare host handed to `loadUrl` was the blank page); an address that still cannot be loaded answers `invalid_arguments` (*"That address can't be opened."*) instead of opening a blank tab. |
| C6 | housekeeping | `hello.features` gains `web_home`, `web_fullscreen`, `web_bookmark_add`, and `web_mouse` **only when `SendInput` is bound** (`RemoteService.helloFeatures`); `proto` stays 1. `RemoteErrorCode.noWebMouse` added — **still to mirror into `salu-remote/lib/protocol/remote_protocol.dart`** (that repo is not part of this checkout; its copy on `main` is also still missing A6's `no_web_tabs` / `tab_not_found` / `no_web_bookmarks`). `remote.md` §17.3 file map updated. |
| C6 | tests | `test/remote_web_fullscreen_test.dart` (page vs window selection, refused request → real click, all-refused → window, no control → window, `on:false` leaves both / twice, already-fullscreen no-op, ack shape, invalid `on`, `web_media_get.fullscreen` from the document and from the host, plan-script selectors, the feature list, `browser_nav home`), `test/remote_mouse_test.dart` (exact relative moves, adding up, DPR scaling with carry, no own acceleration, ±320 clamp, click 1 vs 2, middle/right/defaults, invalid button/count, `no_web_mouse` unavailable and blocked, never awaits), `test/remote_bookmarks_test.dart` (append one, same URL once, nothing else changes, scheme + invalid, full store, no rename/delete verb). The existing exact-shape round-trip in `test/remote_web_media_test.dart` gains the new `fullscreen:false` key. |
| C7 | last-tab mirror reset (audit note) | In `browser_screen.dart`'s `_closeTab` when `_tabs.isEmpty`: call `_browserService.setRemoteWebMirror(title: null, url: null, canBack: false, canForward: false, loading: false, tabCount: 0)`. The phone now guards against stale title/url when `tabs: 0`, but clearing the mirror on the PC keeps the snapshot wire state completely clean. |

**Honest limits.** This sandbox has no Flutter SDK (and no route to pub.dev), so `flutter
analyze` / `flutter test` have **not** been run here — run them first on the PC. The injected
page scripts were syntax-checked and smoke-run under Node against a YouTube-shaped mock DOM
(control found by selector, by bottom-right strip, *exit* label skipped, no player →
`found:false`). The live behaviours — YouTube actually going fullscreen from the phone, the
cursor moving on the real screen — are C6.6's acceptance list and need the user's PC.

---

## Part A — the web section (2026-09-23)

### A0. What the user reported, and what it means

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

### A1. Make the units explicit — `remote_web_media_bridge.dart`

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

### A2. Find the page's real player, not its advert

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

### A3. `web_key` and `web_focus_get` — the D-pad (phone side: built)

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

### A4. The tab strip mirror — list, switch, close, new (phone side: built)

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

### A5. The bookmark mirror — read-only (phone side: built)

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

### A6. Housekeeping that must not be skipped

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

### A7. Tests to add on the PC side

| File | Covers |
|---|---|
| `test/remote_web_media_test.dart` | The unit conversions both ways (ms ↔ `currentTime`, percent ↔ `el.volume`); `NaN`/`Infinity` → `0` + `seekable:false`; `to` clamping at both ends; `delta` from the current seat; seek coalescing (three `to`s in a beat → one injection, the newest) |
| `test/remote_web_find_test.dart` | The element pick: a playing visible element beats a larger hidden one; sub-2-second and zero-box elements are ignored; a cross-origin-iframe page answers `found:false` |
| `test/remote_web_tabs_test.dart` | The mirror follows add/remove/select/title changes; a stale index → `tab_not_found`; a negative index → `invalid_arguments`; 200 tabs → ≤ 50 rows and an encoded frame under 8 KB; `count` still tells the truth |
| `test/remote_web_focus_test.dart` | The focus order and its filters; text-field caret mode (`editable:true`); `Enter` clicks vs submits; `Escape` order (element → page → dialog); the ack's `focus` payload shape |

### A8. Acceptance checklist (verify on the user's PC, in this order)

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

### A9. Order of work

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

### A10. Before shipping the phone side (one honest caveat)

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
| `lib/ui/dpad.dart` | **deleted 2026-09-24** — replaced by `lib/ui/mouse_pad.dart` (the trackpad, Part C3). The `web_key` verbs stay: the pad's double tap is still `Enter` |
| `lib/ui/tune_tab.dart` | Web mode always shows the pad — since 2026-09-24 it is the **trackpad** and one line (Part C3) |
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

### Part A — implementation record (2026-09-24)

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

## Part B — the `fs_places` drive scan, the group-by pill and channel grouping (2026-09-22)

> Kept exactly as written. §12 is a record of phone-side work, not a work order.

### 1. The bug (confirmed from the code, 2026-09-22)

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

### 2. The rule that fixes it (non-negotiable)

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

### 3. Changes in `lib/core/remote/remote_fs_service.dart`

No new packages: use `dart:ffi` against `kernel32.dll` / `shell32.dll`. Declare
`ffi: ^2.1.0` in `pubspec.yaml` for the `calloc` helpers (already in the lockfile
transitively via `shared_preferences_windows`; pure Dart, zero native code added).

#### 3.1 Replace `_drives()` with a table-driven scanner

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

#### 3.2 Labels, and skipping empty removable/optical drives

For each surviving letter, call `GetVolumeInformationW(root, …)`:

- returns a label → `name = 'Label (X:)'`;
- returns an empty label → Explorer-style fallback: `Local Disk (X:)` (fixed),
  `Removable Disk (X:)` (removable), `Disc Drive (X:)` (optical),
  `RAM Disk (X:)` (ram);
- the call **fails** (no media / not ready — empty card reader, empty DVD tray) →
  **skip the drive entirely** (matches Explorer's default of hiding empty drives).

**Never call `GetVolumeInformationW` on a `DRIVE_REMOTE` letter** — filtering
happens first, always.

#### 3.3 Keep the handler non-blocking

`_localDrives()` itself is microseconds; the label reads are the only part that can
stall (a sleeping USB disk). So:

- run the label pass with `Isolate.run(...)` guarded by
  `.timeout(const Duration(seconds: 2), onTimeout: …)`;
- on timeout, answer with the letters and bare-letter names — never block;
- cache the result ~5 s so a burst of `fs_places` calls costs nothing.

`places()` therefore becomes `Future<RemoteFsPlaces> places({String? nowPlayingPath})`.
Update its single call site accordingly (§4).

#### 3.4 Quick places: stop guessing user folders

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

#### 3.5 Now playing: same network guard

Current code checks `Directory(parent).existsSync()`. Before that check:

- `current.contains('://')` → skip (already there);
- `parent` is UNC or its root letter is `DRIVE_REMOTE` → **skip without any I/O**;
- otherwise the local `existsSync` is safe and stays.

#### 3.6 Reply shape (additive, backward compatible)

Each drive place gains one field; everything else is unchanged:

```json
{ "name": "Local Disk (C:)", "path": "C:\\", "kind": "drive", "medium": "fixed" }
```

- `medium` ∈ `fixed | removable | optical | ram` (drives only; omit elsewhere).
- Older phone builds ignore unknown fields — safe. The current phone build
  (salu-remote, already updated) uses `medium` for the chip icon and additionally
  hides any place flagged `net:true`, kind `network*`, or a UNC path — the PC
  should simply never send network-backed places, which is the real guarantee.

### 4. Changes in `lib/core/remote/remote_command_handler.dart`

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

### 5. Linux/macOS builds

`GetLogicalDrives` is Windows-only. Guard with `Platform.isWindows`:
non-Windows keeps today's behaviour (no drive letters; explicit paths still work —
the feature stays honest, per the existing comment). The quick-place resolution may
fall back to `USERPROFILE`/`HOME` + `existsSync` off Windows as today.

### 6. Tests — extend `test/remote_fs_test.dart`

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

### 7. Docs to mirror (if present in this repo)

If this repo carries its own copy of `remote.md`, mirror the three amended spots
(already changed in `hamamun/salu-remote`): §17.3 `remote_fs_service.dart` row,
the `fs_places` verb row (new `medium` field), and the §17.6
"Drives are enumerated, network shares are not" rule. `pc_part.md` is authoritative
where copies have drifted.

### 8. Out of scope — do not change

- The 3 s `busy` handler timeout, the phone's timeouts, the auth/pairing flow.
- No write API in `RemoteFsService` (read-only by design — keep it absent).
- No PowerShell / WMI / `wmic` subprocesses — the fix is pure Win32 FFI.
- No UI changes in the PC player's own screens.

### 9. Acceptance checklist (verify on the user's PC shape)

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

### 10. Group-by pill does not open while a phone is connected (investigate and fix)

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

### 11. Channel grouping on the phone (new protocol + PC duties)

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

### 12. Phone-local channel favourites + queue search (no PC work needed, future sync optional)

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

---

# Part 6 · Audit: this file against the code (2026-09-30)

Parts 1–5 are design documents: they were written before and during the build, and Parts 3 and 5 describe a *different* repository (`hamamun/Salu`) that is not in this checkout. This Part is the check the other four never had — every fact the Android side of this repository can be asked about was extracted **from the code** and searched for in this document.

Both halves are scripts kept in the repository root, so the check is repeatable instead of a claim:

- `python3 tool_compile_doc.py` — rebuilds this file from the five originals (they are in git history at the commit before this one).
- `python3 tool_audit_doc.py` — re-runs the audit. Add `--inherited` to measure Parts 1–5 alone, which is what the table below reports.

## 6.1 What the inherited Parts 1–5 did not cover

| Extracted from the code | Found in the five original documents | Not mentioned in any of them |
|---|---|---|
| verbs the phone sends | 72 / 72 | — |
| `hello.features` flags | 10 / 10 | — |
| error codes | 28 / 35 | `auth_failed`, `invalid_response`, `library_full`, `not_paired`, `not_private_lan`, `remote_off`, `too_many` |
| permission | 2 / 3 | `ACCESS_NETWORK_STATE` |
| method channel | 1 / 2 | `app.salu.remote/deep_link` |
| scheme/host | 1 / 1 | — |
| sdk pin | 1 / 1 | — |
| gradle pin | 3 / 3 | — |
| dependency | 2 / 6 | `^3.13.3`, `connectivity_plus`, `cupertino_icons`, `flutter_lints` |
| Dart source files | 23 / 47 | `lib/core/connect_failure.dart`, `lib/core/deep_link.dart`, `lib/core/pc_address.dart`, `lib/core/queue_view.dart`, `lib/ui/audio_tracks.dart`, `lib/ui/browse_tab.dart`, `lib/ui/connect_sheet.dart`, `lib/ui/equalizer.dart`, `lib/ui/files_browser.dart`, `lib/ui/play_tab.dart`, `lib/ui/qr_scan.dart`, `lib/ui/queue_card.dart`, `lib/ui/settings_sheet.dart`, `lib/ui/subs_search.dart`, `lib/ui/subtitles.dart`, `lib/ui/widgets.dart`, `test/connect_failure_test.dart`, `test/deep_link_test.dart`, `test/mouse_pad_test.dart`, `test/pc_address_test.dart`, `test/power_client_test.dart`, `test/power_menu_test.dart`, `test/track_info_test.dart`, `test/widget_test.dart` |

*(Measured against the five originals as they were, before this compiler touched them. The one correction note injected into Part 2 §4 on 2026-09-30 already names `ACCESS_NETWORK_STATE`, `app.salu.remote/deep_link` and `connectivity_plus`, so re-running `tool_audit_doc.py --inherited` against the compiled file reports three fewer gaps than this table does.)*

**The reverse direction is clean too.** 15 verb-shaped names appear in Parts 3–5 that this phone never sends: 7 of them are `hello.features` flags rather than verbs, and the other 8 are `browser_back`, `browser_get`, `browser_reload`, `browser_tabs`, `repeat_one`, `seek_chapter`, `web_mouse_scroll`, `web_scroll`. Every one of those is accounted for in the text — `seek_chapter`, `browser_back`, `browser_reload`, `browser_tabs` and `browser_get` are Part 3 §9's "reserved for v2" list, `web_mouse_scroll` / `web_scroll` are Part 5 C3's "not built, not ordered" wheel verb, and `repeat_one` is an icon name. Nothing in the specification promises a verb the code forgot.

Read that table like this: **the protocol is complete and the surroundings were not.** Every verb the phone can put on the wire and every `hello.features` flag it understands was already specified in Part 3 — nothing there was invented at build time. What the four inherited documents never listed is the *local* half of the app: the failure codes the phone raises against itself rather than receiving from the PC, one Android permission, one method channel, two dependencies, and 24 of the 47 Dart files. Sections 6.2–6.4 below close each of those; after them the audit reports full coverage of the whole file.

## 6.2 The phone's complete error vocabulary

`lib/core/error_copy.dart` is the one place a failure becomes a sentence, and it is the authority for this table — Part 3 §6.4 and §17.8 list only the codes the **PC** sends. Codes marked *new here* appear in no inherited Part; they exist because the phone has failure modes of its own, and a code with no sentence would have reached the user as a blank row.

| Code | Where it comes from | The phone shows |
|---|---|---|
| `bad_code` | PC (Part 3 §6.4) | That pairing code is not valid. |
| `bad_token` | PC (Part 3 §6.4) | This phone is no longer paired. |
| `version_mismatch` | PC (Part 3 §6.4) | Update SALU Remote — the PC speaks a different version. |
| `nothing_playing` | PC (Part 3 §6.4) | Nothing is playing on the PC. |
| `not_seekable` | PC (Part 3 §6.4) | This stream can't be seeked. |
| `unknown_command` | PC (Part 3 §6.4) — **silent** | nothing; it is how a missing feature flag is detected |
| `too_fast` | PC (Part 3 §6.4) — **silent** | nothing; the read lane backs off on its own (Part 5 F0) |
| `no_preset` | PC (Part 3 §17.8) — **silent** | nothing; logged |
| `file_access_off` | PC (Part 3 §17.8) | File browsing is turned off on the PC. |
| `path_not_found` | PC (Part 3 §17.8) | That folder or file is no longer there. |
| `not_a_directory` | PC (Part 3 §17.8) | That path is not a folder. |
| `no_media` | PC (Part 3 §17.8) | Nothing is playing on the PC. |
| `no_key` | PC (Part 3 §17.8) | Add an OpenSubtitles key on the PC to search. |
| `signed_out` | PC (Part 3 §17.8) | Sign in to OpenSubtitles on the PC to download subtitles. |
| `quota` | PC (Part 3 §17.8) | OpenSubtitles download limit reached. Try again tomorrow. |
| `no_web_media` | PC (Part 3 §17.8) | This site's player can't be controlled from outside. |
| `busy` | PC (Part 3 §17.8) | The PC is busy — try again in a moment. |
| `invalid_arguments` | PC (Part 3 §17.13.2) | The PC didn't understand that request. |
| `no_web_tabs` | PC (Part 5 A6) — **not yet mirrored into `remote_protocol.dart`** | Tab control needs an updated SALU on the PC. |
| `tab_not_found` | PC (Part 5 A6) — **not yet mirrored** | That tab is no longer open. |
| `no_web_bookmarks` | PC (Part 5 A6) — **not yet mirrored** | The PC's browser has no bookmarked pages. |
| `no_web_mouse` | PC (Part 5 C6) — **not yet mirrored** | The PC couldn't move its pointer. |
| `stale_queue` | PC (Part 5 F2) — **new here** | The playlist changed. (the phone then re-reads state) |
| `too_large` | PC (Part 5 F2), or the phone's own 8 KB write guard — **new here** | The request or response is too large. |
| `invalid_response` | phone, `lib/core/queue_reader.dart` (Part 5 F2 fragment validation) — **new here** | Invalid playlist response. |
| `library_full` | PC, no producer on this side — **new here** | The saved stream list is full. |
| `offline` | phone, `lib/core/reply.dart` — no open socket | Not connected to your PC. |
| `timeout` | phone, `lib/core/client.dart` — the 8 s command budget | The PC did not answer in time. |
| `remote_off` | phone, naming close code **4004** — **new here** | Remote control is switched off in SALU on the PC. |
| `not_private_lan` | phone, naming close code **4003** — **new here** | The PC only accepts phones on its own local network. |
| `too_many` | phone, naming close code **4005** — **new here** | The PC has too many remote connections already. |
| `auth_failed` | phone, naming close code **4001** — **new here** | The PC did not accept this phone. |
| `unreachable` | phone, `lib/core/connect_failure.dart` | Can't reach the PC. |
| `refused` | phone, `lib/core/connect_failure.dart` | That address is not a SALU Remote. |
| `not_paired` | phone, local state — **new here** | This phone is not paired with the PC yet. |

Two things this table settles that the inherited Parts left ambiguous:

1. **Four codes are specified but not yet mirrored.** Part 5 A6.2 and C6.2 both order `no_web_tabs`, `tab_not_found`, `no_web_bookmarks` and `no_web_mouse` into `lib/protocol/remote_protocol.dart`. As of this audit that file's `RemoteErrorCode` still ends at `invalid_arguments` and has none of the four — the phone displays them correctly anyway, because `error_copy.dart` keys off the wire string and not off the constant. The mirror is still owed: the file's own header calls the two copies *"one file with two addresses"*.
2. **`library_full` has no producer on this side.** It is display-only copy for a PC that answers a full saved-stream list (the PC's `UrlLibraryService` caps at 7 entries — Part 4 §5.2). Nothing in `lib/` raises it.

## 6.3 The Android surface as it actually is

Part 2 §4.1 and §4.3 carry the manifest and `MainActivity.kt` as they were written, and they predate two things the app now needs. **The files below are the current ones — verify against these, not against Part 2's samples, and never paste a sample over them.**

| Fact | Value in this checkout | In Parts 1–5? |
|---|---|---|
| Permissions | `ACCESS_NETWORK_STATE` · `CAMERA` · `INTERNET` | `ACCESS_NETWORK_STATE` was not mentioned |
| Method channels | `app.salu.remote/deep_link` · `app.salu.remote/screen` | `app.salu.remote/deep_link` was not mentioned |
| Intent filter | `salu://pair` (`android:scheme="salu"` + `android:host="pair"`) | yes |
| `minSdk = 24` (was `flutter.minSdkVersion`) | 24 | yes |
| Gradle · AGP · Kotlin | Gradle `9.3.1` · AGP `9.1.0` · Kotlin `2.4.0` | yes (Part 1, the whole Java/Gradle section) |
| Dependencies | Dart SDK `^3.13.3` · `cupertino_icons: ^1.0.8` · `shared_preferences: ^2.2.3` · `mobile_scanner: ^7.0.0` · `connectivity_plus: ^7.3.1` · `flutter_lints: ^6.0.0` | `connectivity_plus`, `cupertino_icons` and `flutter_lints` were not mentioned |

`ACCESS_NETWORK_STATE` and `connectivity_plus` are the same change from two sides: Part 5 E0.3 promises *"network-up events redial at once"*, and that is `connectivity_plus` listening for a network change — which on Android requires the permission. `app.salu.remote/deep_link` is the second door of D2's QR pairing: a scan handled by the *camera app* arrives as an intent, so `MainActivity` keeps the last link and answers `getInitial` on a cold start, and pushes `onLink` when the app is already open (`launchMode="singleTop"` → `onNewIntent`). Part 2 §4.3's sample has neither.

These two blocks are **read from disk at compile time**, so they cannot be older than the repository:

##### `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <application
        android:label="SALU Remote"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="salu" android:host="pair" />
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

##### `android/app/src/main/kotlin/app/salu/salu_remote/MainActivity.kt`

```kotlin
package app.salu.salu_remote

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val screenChannel = "app.salu.remote/screen"
    private val linkChannel = "app.salu.remote/deep_link"

    // The most recent salu:// link the OS handed to us. `getInitial` reads it
    // so a cold start from a scanned QR is never lost to the Dart/engine race.
    @Volatile
    private var lastLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linkChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitial" -> result.success(lastLink)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sendLink(intent?.data)
    }

    // launchMode is singleTop, so a second QR scan while the app is open
    // arrives here rather than in onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sendLink(intent.data)
    }

    private fun sendLink(data: Uri?) {
        if (data == null) return
        lastLink = data.toString()
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        MethodChannel(messenger, linkChannel).invokeMethod("onLink", lastLink)
    }
}
```

## 6.4 The file map — every Dart file in this repository

24 of these 47 files are named nowhere in Parts 1–5. Listed in full so that working from this one file means knowing the whole tree.

| File | What it is |
|---|---|
| `test/pc_address_test.dart` | The address box: `host:port`, a bare host, a URI, and junk. |
| `lib/ui/qr_scan.dart` | The in-app camera scanner (`mobile_scanner`) — the other half of D2. |
| `lib/core/pc_address.dart` | Makes sense of the address box — `192.168.0.12`, `…:7258`, a `salu://pair` URI — defaulting to port 7258 (Part 3 §8.1). |
| `lib/ui/settings_sheet.dart` | The phone's own settings: the name the PC shows, and the permanent show/hide checklist. |
| `lib/core/screen.dart` | Keep-screen-awake over the `app.salu.remote/screen` channel — one window flag, deliberately not a plugin. |
| `test/widget_test.dart` | First launch: header, the three tabs, and the connect sheet opening on a fresh device. |
| `test/connect_failure_test.dart` | Socket errors classified into `unreachable` vs `refused`. |
| `test/queue_view_test.dart` | The accordion, search and favourites paint list. |
| `lib/core/models.dart` | Typed views over the PC's values — snapshot, playback, queue, web, tune, subs; `WebMediaInfo`'s unit detection; the tab/bookmark/focus parses; `RemoteFeature`. |
| `lib/ui/root.dart` | The shell: header (dot · name · focus · ⋮), three tabs, the mini now-playing strip, the connect sheet, and the ⋮ menu with Sleep PC / Shut down PC. |
| `test/track_info_test.dart` | Track names: a readable language label, never a duplicated generic `Track`. |
| `lib/ui/web_tabs_card.dart` | The collapsible **Open tabs** section at the foot of the Web body — the queue card's shape, the queue card's memory. |
| `lib/ui/equalizer.dart` | Tune → Equalizer: the live curve, the PC's presets, ten sliders, Speed chips, Auto EQ. |
| `lib/core/connect_failure.dart` | Turns a Dart socket exception into `unreachable` (retry) or `refused` (that address is not SALU), with the sentence to match. |
| `lib/ui/browse_tab.dart` | Tab 2 shell: the Files | Streams switch, greyed with a reason while the PC is in Web mode. |
| `lib/ui/subs_search.dart` | The OpenSubtitles search screen, pre-filled with the PC's current title. |
| `test/web_url_test.dart` | `webAddress` (the blank-tab fix) and `homeOrigin`. |
| `lib/main.dart` | The app itself: `SaluRemoteApp`, pairing and preferences loaded before the first frame, deep links registered. |
| `lib/core/reply.dart` | One reply type for every verb: ok, error, typed result, or the phone's own `offline`. |
| `test/browse_seat_test.dart` | The Browse seat greys in Web mode **and** un-greys on the way back — both directions, with the sentence on tap (Part 3 §17.9 step 29). |
| `test/deep_link_test.dart` | `salu://pair` parsing: `v` · `n` · `h` · `p` · `c`, and the rejects. |
| `lib/ui/connect_sheet.dart` | The one place pairing happens: QR · manual · paste, diagnostics, **Connection history** (Part 5 F0), remember me. |
| `lib/ui/audio_tracks.dart` | Tune → Audio: the audio-track list, mirroring the PC's selection. |
| `test/queue_reader_test.dart` | Part 5 F2's lane: paging, the `too_large` shrink, `stale_queue`, fragment merge and coverage validation. |
| `test/mouse_pad_test.dart` | The trackpad's maths and gestures: 2.5× gain, ±320 px clamp, 40 ms batching, and the one line. |
| `lib/core/web_url.dart` | Two pure functions: `webAddress` adds the scheme (the blank-new-tab fix) and `homeOrigin` computes the Home button's target. |
| `lib/core/queue_reader.dart` | The paced, serial, byte-budgeted read lane for `queue_get` / `queue_groups_page` — playback and heartbeats never wait behind it (Part 5 F0/F2). |
| `lib/ui/subtitles.dart` | Tune → Subtitles: tracks, sync, the file picker, auto-download — the PC does the work. |
| `lib/ui/queue_card.dart` | The playlist: 5 visible rows, auto-scroll, tap to jump, ✕ to clear, search, favourites and the grouping accordion. |
| `lib/ui/widgets.dart` | Shared furniture: fire-a-verb-and-say-why, collapsible section headers, the activity dot, the one honest line for a dead end. |
| `test/power_menu_test.dart` | The ⋮ menu in Player, Web and Focus mode: disabled states, confirmations, nothing sent on cancel. |
| `lib/core/client.dart` | The one connection: auth, reconnect with backoff, snapshot application, one thin wrapper per verb, the retry lane, the 10 s transport keepalive and the 5 s `ping` speedometer. |
| `lib/core/queue_view.dart` | The queue card's paint list, pure: accordion, search filter, favourites filter — testable without a widget. |
| `test/power_client_test.dart` | `pc_sleep` / `pc_shutdown` on the wire, gated on `pc_power`, sent exactly once. |
| `lib/core/deep_link.dart` | The second QR door: parses `salu://pair` and talks to the `app.salu.remote/deep_link` channel (`getInitial` on a cold start, `onLink` while open). |
| `lib/protocol/remote_protocol.dart` | **Copied from the PC repo — do not edit separately.** `proto: 1`, the 8 KB cap, close codes 4001–4005, `RemoteErrorCode`, `RemoteSnapshot`. |
| `lib/core/prefs.dart` | What the phone remembers: the paired PC and its token, plus focus mode, the show/hide checklist, collapse states and channel favourites by title. |
| `test/web_media_test.dart` | Unit detection and write-side conversion, plus the tab / bookmark / focus parses. |
| `lib/ui/files_browser.dart` | Browse → Files: breadcrumb, quick places, local drives only, 200-row pages, multi-select, and subtitle-picker mode. |
| `lib/ui/web_sheets.dart` | ☆ Saved pages (bookmarks only) and the long-press **Web diagnostics** sheet. |
| `lib/ui/streams.dart` | Browse → Streams: the PC's own URL library mirrored, with add / rename / delete and the PC's health dot. |
| `lib/ui/theme.dart` | SALU's palette ported from the PC, and `LiveSlider` — the app's one slider (streams while dragging). |
| `lib/ui/tune_tab.dart` | Tab 3 shell: Equalizer | Subtitles | Audio — or, in Web mode, the mouse pad and nothing else. |
| `lib/ui/web_body.dart` | The Play tab in Web mode, both shapes — the nav row and the page doors, or the page player's own controls. |
| `lib/core/error_copy.dart` | Every failure in plain words (§6.2), plus the set the specs deliberately keep silent. |
| `lib/ui/play_tab.dart` | Tab 1 in Player mode: transport row, repeat · shuffle · start-over row, live sliders, the full-width Player·Web switch, focus mode. |
| `lib/ui/mouse_pad.dart` | The trackpad, the two ▲▼ scroll seats and the one `Mouse` line. |

`lib/ui/dpad.dart` is deliberately absent: Part 4 §6.0 deleted it on 2026-09-24 in favour of `lib/ui/mouse_pad.dart`, and Part 5 C6.4 records the same. `lib/ui/theme.dart` likewise no longer has `CommitSlider` (Part 5 A10 — `LiveSlider` is the app's one slider).

## 6.5 What this audit could not check

Stated plainly, because an audit that hides its own blind spot is worse than none:

- **`flutter analyze` and `flutter test` were not run.** This sandbox has no Flutter or Dart SDK, and the download is blocked at the TLS layer — the same limitation Part 5 A10 and F5 already record for the phone side. Everything in 6.1–6.4 is a **static** reading of the source: grep and parse, no compilation, no test run. The 13 files in `test/` are described, not executed.
- **Nothing on the PC side was verified at all.** `hamamun/Salu` is not in this checkout, so Parts 3 and 5 are reproduced as written. Their *"implementation record"* tables say the work landed in that repository; that claim could not be checked here and is not endorsed by this audit.
- **The live behaviours are still open.** YouTube actually going fullscreen from the phone, the PC cursor moving under a thumb, sleep/wake reconnection — those are the acceptance checklists in Part 5 (A8, C6.6, E8, F5) and they need the user's own Windows PC and a paired phone.

---

# Part 7 · Connection reliability, round two — the busy PC (2026-09-30)

> **Hand-written, and deliberately outside the compiler.** `tool_compile_doc.py`
> produces Parts 1–6 from the five original documents; this Part is written
> against the code as it stands today, so re-running that script would drop
> it. Re-add it, or promote it into the script's `PARTS` list, before relying
> on a rebuild.

> **Why this exists — the user's words, three weeks after Part E:** *"still its
> happening and remian busy"*, and, asked when: **while the app is open on
> screen**, with **the remote's UI lagging**, **the blue activity dot on**, and
> **the link reconnecting**. Not after the phone slept. Not after the PC slept.
> In the hand, in use.

Part E fixed *who declares death*: the transport, not a command that came back
late. That was right, and it was not enough, because the transport rule itself
was still built on an assumption this PC violates. Everything below was
confirmed by reading the sources on both sides — `lib/core/client.dart` here,
and `hamamun/Salu` at `561bd50` (`lib/core/remote/remote_service.dart`,
`remote_command_handler.dart`, `queue_grouping_cache.dart`).

## 7.1 The four mechanisms that were still dropping the link

| # | Mechanism | Where it lived | Why it bit |
|---|---|---|---|
| 1 | **`pingInterval` is a deadline, not a cadence.** Dart sends a ping after `pingInterval` and closes the socket with `1001` when the pong is more than another `pingInterval` late (`sdk/lib/_http/websocket_impl.dart`, `set pingInterval`). At 10 s the phone demanded a protocol-level pong inside 10 s — **inside the window a PC blocked for 10–30 s (Part B §1) cannot answer at all.** | `client.dart` `_open()` | The user's PC has many disconnected mapped drives. Any stall long enough to delay the pong was answered by the phone tearing the link down. |
| 2 | **A frame is not an answer, but an answer is not the only frame.** dart:io's pong timer is reset only by a **PONG** frame. A PC pushing snapshots at 4/s while too busy to answer a command was killed anyway, because it never wrote the pong. | same | Directly contradicts Part E2's own rule: *command-path delays are not evidence of a dead link.* |
| 3 | **A busy PC looks like an unpaired one.** The PC reaps any socket that has not completed `auth` within 5 s (`remote_service.dart` `_authTimer`, Part 3 §7.1.6) with `auth_timeout` + close `4001`. `auth_timeout` and `auth_failed` were both in the phone's *_noRetryCodes* set, so one stalled handshake stopped the loop dead and demanded a re-pair — of a token that was still perfectly good. | `client.dart` `_noRetryCodes` | The worst possible failure mode: the PC gets busier, so the phone gives up on it. |
| 4 | **The phone kept re-arming the stall.** `fs_places` is the one verb that has blocked this PC for tens of seconds. The files browser is rebuilt whenever the snapshot returns after a gap, and `initState` asked for the drive table again — so: request → PC stalls → looks dead → drop → screen rebuilds → request. A closed loop. | `files_browser.dart` `_loadPlaces()` | Each turn of the loop re-created the evidence that justified the next turn. |

Two smaller ones, same family:

- **Resume killed healthy sockets.** `onResume()` proved the link with a
  3-second `state_get` and tore the socket down when it came back late — the
  one place the phone still punished a slow answer as if it were a dead link.
- **A Wi-Fi roam killed healthy sockets.** Android reports `none` while Wi-Fi
  hands off between access points, and the network watcher dropped the socket
  on that first word.

## 7.2 The rule now, in two sentences

Everything lives in one pure class, `lib/core/link_health.dart`, so it is
testable without a socket (`test/link_health_test.dart`):

- **Dead = silence.** Not one frame of *any* kind — `state`, `ack`, `pong`,
  even an unparseable frame — for **25 s**. Any frame resets the clock, so a
  PC that is still talking is never killed for being slow.
- **Busy = slow answers.** An unanswered `ping` older than **2 s**, or a
  command the PC refused with `busy` / `too_fast` (Part 3 §7.3, §17.8), or one
  that timed out. Nothing is *ever* disconnected for this.

| Knob | Was | Now | Why |
|---|---|---|---|
| transport `pingInterval` | 10 s | **25 s** | Backstop only. Must never fire on a PC that is merely blocked. |
| death declared by | missing pong (≈20 s) | **silence (25 s)** | 5 s slower on a genuinely dead link, infinitely more forgiving of a stalled one. |
| app `ping` | 5 s, killed the link | 5 s, measures latency **and** proves life | It is the proof of life while nothing is playing. |
| `state_get` on resume | 3 s, teardown on timeout | 6 s, **no teardown** | A late answer is a slow PC. Silence, or a failed write, is a dead one. |
| network gone | teardown at once | **2.5 s grace, then re-check** | Survives AP handoffs and mobile-data flapping. |
| `auth` hiccup | stop, ask to re-pair | **retry ×3, then stop** | Only a credential refusal (`bad_code`, `bad_token`, …) stops on the first one. |
| dial backoff | 1·2·3·5·8·12 s | 1·1·2·3·5·8·12 s | A PC that comes back is picked up within a second. |

`_onClosed`'s close-code switch lost one behaviour worth naming: **close `4001`
no longer stops the loop.** It is routed through `_onAuthFailure()` with the
other retryable handshake failures. `4002`, `4003`, `bad_code`, `bad_token` and
`version_mismatch` still stop it — those are answers, not stalls.

## 7.3 What the phone stopped asking for

A remote cannot make a busy PC faster, but it can stop adding to the queue.
Every change below is work the phone volunteered, not work a thumb asked for:

| Load | Was | Now |
|---|---|---|
| Tune panes (EQ · Subs · Audio) | 1 read/s each, unconditionally | **1 read / 2 s**, and skipped entirely while the PC is flagged busy |
| Web-media poll | 1/s, unconditionally | 1/s, skipped while busy, refreshed the moment it clears |
| Playlist read lane | 100 ms between pages (**10 reads/s**) | **200 ms (5/s)**, and the lane *yields* while the PC is flagged busy (bounded at 10 s, so a playlist still arrives) |
| Stall nudge (`state_get`) | every 5 s while snapshots stall | skipped while the PC is flagged busy |
| `fs_places` | on every rebuild of the files browser | **once per PC per session**; the user's "Try again" forces it |

Context for the playlist row: the PC's whole budget is **30 commands/second**
(Part 3 §7.3) and the trackpad alone spends 25 of those (Part 5 C3). A read
lane taking ten a second left almost nothing for the thumb — which is why
interactive controls came back `busy` while a 50,000-channel list loaded.

## 7.4 What the user can see

- The Connect sheet gained a **PC load** row: *"Keeping up"* or *"Busy — the
  remote is giving it room"*. That is the flag the read lanes obey, so the
  screen now agrees with the behaviour.
- Every entry in **Connection history** carries `silent <ms>` and
  `busy yes/no` alongside the close code, so a drop can be told apart from a
  stall after the fact — the thing Part 5 F4.5 asked both logs to be able to
  do.

## 7.5 What `hamamun/Salu` still owes (Part G)

Small, and all of it in `lib/core/remote/remote_service.dart`. None of it
needs a protocol change.

- **G1 — `ping` must not spend the rate-limit budget.** `_message()` counts the
  command into `_commands` *before* the E1 shortcut answers it, so during a
  trackpad drag (25 moves/s) a `ping` can be dropped with `too_fast` — and the
  phone then marks the PC busy for no reason. Answer `ping`, then count, or do
  not count it.
- **G2 — the 5-second auth reap is too tight for a stalled machine.** Raise it
  to ~10 s, or exempt a socket that has already delivered a well-formed `auth`
  frame (the PC is busy, not being probed). Every `auth_timeout` costs a
  reconnect cycle and, after three, a re-pair prompt the user has to dismiss.
- **G3 — `socket.pingInterval = 20 s` is the same deadline trap, mirrored.**
  dart:io will close a phone whose own event loop has been busy for 20 s.
  30 s costs nothing; the phone's silence rule is the one that matters now.
- **G4 — log the split.** `remote_connection_log.dart` records last frame and
  last heartbeat; add *last command answered* and *snapshot cadence*, so the
  two logs can be lined up and a stall can be proved rather than guessed at
  (Part 5 F4.5).

## 7.6 Acceptance checklist — the user's own PC, in this order

1. **The stall test.** With nothing playing, open a folder on the PC that
   contains a disconnected mapped drive (or any known-slow scan). The phone's
   header dot must stay green; **no** "Reconnecting…", **no** re-pair prompt.
   The Connect sheet's *PC load* row may read *Busy*.
2. **The recovery test.** Let the PC finish the scan. The phone's panes refresh
   on their own within a couple of seconds; *PC load* returns to *Keeping up*.
3. **The roam test.** Walk between two access points with the remote open. No
   reconnect cycle (a cycle is visible as a new *Connection history* entry).
4. **The screen-off test.** Lock and unlock the phone while a video plays. The
   picture returns within a frame or two; the log shows no
   `link declared dead`.
5. **The dead-link test.** Close SALU on the PC. The phone notices within about
   25 s, shows *Reconnecting…*, and reconnects within a second of SALU
   reopening — no re-pair.
6. **The pairing test.** Type a wrong pairing code on purpose. It must still
   fail immediately, with *"That pairing code is not valid"*, and must **not**
   retry — the one behaviour that must not have become more patient.

## 7.6a What this Part could not check

`flutter analyze` and `flutter test` were **not run** — this sandbox has no
Flutter or Dart SDK and the download is blocked at the TLS layer, the same
limitation Part 6.5 records. `test/link_health_test.dart` is written, not
executed; treat it as a specification of the policy with the same standing as
the policy's prose until it has been run once on a machine with the SDK.
