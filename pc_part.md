# Part F — large playlists, grouping parity and Web-mode stability (2026-09-26)

**Status: Remote implementation written in this branch; PC implementation pending.**
This work order supersedes Part B §11's `start + count` membership assumption
and Part E's claim that transport keepalive cannot be affected by a busy app.
Do not mark this complete until both apps pass the acceptance tests below.
No PC source has been modified in this Remote session.

## F0. What the Remote now does / rollout

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

## F1. PC playlist panel must observe shared grouping state

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

## F2. Exact, byte-bounded grouping protocol — REQUIRED wire contract

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

### Rows (extension of existing command)

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

### Group membership pages (new read-only command)

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

### Error semantics

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

## F3. Avoid repeated heavy work on the PC

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

## F4. Web-mode polling and disconnect diagnosis

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

## F5. Acceptance / regression checklist

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

# PC part — work orders for the Salu repo

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

# Part E — connection reliability: keep the phone linked (2026-09-26)

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

## E0. What the phone already changed (context — no PC work)

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

## E1. Answer `ping` on the socket path — `lib/core/remote/remote_service.dart`

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

## E2. Socket I/O stays on the main isolate — `remote_service.dart` / architecture check

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

## E3. `state_get` stays prompt under load — `remote_command_handler.dart`

* The phone's stall nudge gives `state_get` **4 seconds** (and its resume health
  check **3 seconds**). The existing 3-second handler guard already fits — verify
  it **cannot be starved**: `state_get` must not sit behind a long `fs_open` scan
  or a burst of trackpad moves in a way that pushes its answer past ~3 s.
* Cheap correct answer beats a late perfect one: if the builder is mid-burst, the
  120 ms event clock (`remote.md` §7.2) still flushes one snapshot; `state_get`
  should trigger that flush and ack even when nothing changed (`ack` with no body
  is fine — the phone only needs *an* answer, plus any pending snapshot).

## E4. Connection bookkeeping — `remote_service.dart`

* **Auth timeout:** keep the 5 s connect→`auth` reap (`remote.md` §7.1.6) — the
  phone's dial-guard (E0.3) means fewer ghosts, but the reap is still the backstop.
* **4005 (max 4):** count only sockets that are actually alive. Free a device's
  slot the instant its socket closes/errors (`onDone`/`onError`), not at the next
  ping tick — the phone reconnects quickly now and must not be refused by a slot
  that is already dead.
* **`socket.pingInterval = 20 s` on the server** (spec §11): keep it; it is the
  PC's own reap of a vanished phone, independent of anything above.

## E5. Fresh-socket snapshot and `rev` — verify only

* `remote.md` §6.1/§7.2 already promise: *new socket = full snapshot immediately,
  `hello` carries a full snapshot, `rev` monotonic per process run.* Verify both
  still hold after any refactor. The phone now force-applies the `hello` snapshot,
  so a PC process restart (rev reset) is also safe — no PC change needed, but do
  not "optimize" the fresh-socket snapshot away; the reconnect paint depends on it.

## E6. Spec rows to fix in `remote.md` (same sitting as the code)

* **§9 `ping` row** — extend the reply column's meaning: *latency display only;
  a late `pong` never means the link is dead (transport keepalive owns death);
  `ping` is answered inline on the socket path (Part E1), never queued behind
  the command isolate.*
* **§7.2 or §11** — one line: *link death is declared by transport-level
  keepalive and close events; command-path delays (busy, `too_fast`, long
  scans) are not evidence of a dead link and must not be treated as such by
  either side.*
* Leave the frame shapes, close codes, and `proto` untouched.

## E7. Tests to add on the PC side

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

## E8. Acceptance checklist (verify on the user's PC, in this order)

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

# Part D — sleep and shut down from the remote's ⋮ menu (2026-09-24)

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

# Part C — the web fixes the user reported after using it (2026-09-24)

> Phone side: **already built** in `hamamun/salu-remote` (`lib/ui/web_body.dart`,
> `lib/ui/web_tabs_card.dart`, `lib/ui/mouse_pad.dart`, `lib/ui/web_sheets.dart`,
> `lib/core/web_url.dart`, `lib/core/client.dart`, `lib/core/models.dart`). Every piece below
> degrades to the phone's current behaviour while the PC has not caught up, so this part can
> land in any order — but the order written here is the order the user will feel it in.
>
> Contract: `remote.md` **§17.14**. This file is the shopping list.

## C0. What the user reported, in their words

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

## C1. One fullscreen seat that actually works — `web_fullscreen`

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

## C2. Home — `browser_nav {action:"home"}`

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

## C3. The trackpad — `web_mouse_move` / `web_mouse_click`

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

## C4. Add-only bookmarks — `web_bookmark_add`

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

## C5. The blank new tab — `web_tab_new {url}`

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

## C6. Housekeeping, tests, and the phone-side file list

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

## Part C — implementation record (2026-09-24)

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
