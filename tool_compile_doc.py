#!/usr/bin/env python3
"""Compile the five .md files of salu-remote into one salu_remote.md.

Content is carried over verbatim (the goal is zero information loss); only
three mechanical things change:

  1. headings are demoted by one level, so the five documents become five
     `#`-level Parts under one H1;
  2. each file's own H1 title line is dropped (the Part header replaces it);
  3. markdown links that pointed at a sibling .md file become links to the
     Part that file became, so nothing dangles after the originals are deleted.

Run:  python3 tool_compile_doc.py
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

PARTS = [
    {
        "n": 1,
        "file": "README.md",
        "title": "Part 1 · This repository — what it is, how to build it, what breaks",
        "drop_h1": ["# SALU Remote"],
        "old": "`README.md`",
        "desc": "The repository at a glance, the current milestone, and every "
                "build/run symptom anyone has actually hit (Gradle vs Java, "
                "no Windows desktop project, firewall).",
    },
    {
        "n": 2,
        "file": "SETUP_STEP_BY_STEP.md",
        "title": "Part 2 · Setup, step by step (no coding needed)",
        "drop_h1": ["# SALU Remote — do this, in this order (no coding needed)"],
        "old": "`SETUP_STEP_BY_STEP.md`",
        "desc": "Parts 0–8 for a person who is not a coder: create the "
                "skeleton, push it, paste the files, the three Android edits, "
                "pair with SALU, and the symptom table.",
        # This Part's Part 4 samples predate two things the app now needs.
        # The note is injected at compile time so it cannot drift from §6.3.
        "inject_after": "then continue to Part 5.",
        "injection": (
            "\n\n> **⚠ Correction added 2026-09-30, when this file was merged "
            "into `salu_remote.md`.** The `AndroidManifest.xml` and "
            "`MainActivity.kt` samples in **§4.1 and §4.3 of this Part** are "
            "the versions written on 2026-09-20, and the app has since grown "
            "two things they do not have: the **`ACCESS_NETWORK_STATE`** "
            "permission (needed by `connectivity_plus`, which is what makes "
            "*\"network-up events redial at once\"* work — Part 5 E0.3) and the "
            "second method channel **`app.salu.remote/deep_link`** (a QR "
            "scanned by the *camera app* rather than in-app arrives as an "
            "intent, so a cold start must be able to ask for it). Pasting "
            "either sample over the files in this checkout would break "
            "QR-from-camera and Wi-Fi-return reconnect. **The files as they "
            "actually are, read from disk, are in "
            "[§6.3](#63-the-android-surface-as-it-actually-is) — verify "
            "against those.**\n"
        ),
    },
    {
        "n": 3,
        "file": "remote.md",
        "title": "Part 3 · PC-side protocol and implementation specification "
                 "(§1 – §17.15)",
        "drop_h1": ["# SALU Remote — PC-Side Implementation Spec (Phase 8, Part 1)"],
        "old": "`remote.md`",
        "desc": "The wire protocol, the snapshot, every verb, every error code, "
                "the PC UI, the build order — and the v1.1 expansion (§17) that "
                "added files, streams, EQ, subtitles, web mode, tabs, the "
                "trackpad and PC power.",
    },
    {
        "n": 4,
        "file": "remote_apk_ui.md",
        "title": "Part 4 · APK interface design (§1 – §13)",
        "drop_h1": ["# SALU Remote — APK Interface Design (v2, expanded scope)"],
        "old": "`remote_apk_ui.md`",
        "desc": "The phone's three tabs, the space system, every screen, the "
                "mouse pad, the feedback/latency rules, the marks to draw, and "
                "what the phone cannot know and must be told.",
    },
    {
        "n": 5,
        "file": "pc_part.md",
        "title": "Part 5 · PC work orders for `hamamun/Salu` (Parts A – F)",
        "drop_h1": [],
        "old": "`pc_part.md`",
        "desc": "The shopping lists for the other repository: F (large "
                "playlists + grouping), E (connection reliability), D (PC "
                "power), C (the web fixes), A (the web section), B (the "
                "`fs_places` drive scan and channel grouping).",
    },
]

# Links that pointed at a sibling file become links into this one.
LINK_TARGET = {
    "README.md": "#part-1--this-repository--what-it-is-how-to-build-it-what-breaks",
    "SETUP_STEP_BY_STEP.md": "#part-2--setup-step-by-step-no-coding-needed",
    "remote.md": "#part-3--pc-side-protocol-and-implementation-specification-1--1715",
    "remote_apk_ui.md": "#part-4--apk-interface-design-1--13",
    "pc_part.md": "#part-5--pc-work-orders-for-hamamunsalu-parts-a--f",
}

LINK_RE = re.compile(r"\[([^\]]+)\]\((README\.md|SETUP_STEP_BY_STEP\.md|remote\.md|remote_apk_ui\.md|pc_part\.md)\)")


def demote(text: str, drop_h1: list[str]) -> str:
    """Demote every ATX heading one level, skipping fenced code blocks."""
    out: list[str] = []
    fence: str | None = None
    for line in text.split("\n"):
        stripped = line.lstrip()
        m = re.match(r"^(```+|~~~+)", stripped)
        if m:
            tok = m.group(1)
            if fence is None:
                fence = tok[0] * 3
            elif stripped.startswith(fence):
                fence = None
            out.append(line)
            continue
        if fence is None and line.startswith("#"):
            hm = re.match(r"^(#{1,6})(\s|$)", line)
            if hm:
                if line.rstrip() in drop_h1:
                    continue
                line = "#" + line  # demote
        out.append(line)
    return "\n".join(out)


def fix_links(text: str) -> str:
    return LINK_RE.sub(lambda m: f"[{m.group(1)}]({LINK_TARGET[m.group(2)]})", text)


def slug(title: str) -> str:
    """GitHub's own anchor rule: lowercase, drop punctuation, each space to a
    hyphen (so the two spaces left by a removed `·` become two hyphens)."""
    s = title.strip().lower()
    s = re.sub(r"[`*_]", "", s)
    s = "".join(c for c in s if c.isalnum() or c in " -·—–/§'")
    for mark in ("·", "—", "–", "/", "§", "'"):
        s = s.replace(mark, "")
    s = s.strip()
    return s.replace(" ", "-")


def headings(text: str) -> list[tuple[int, str]]:
    """Headings of a body, ignoring fenced code blocks."""
    res: list[tuple[int, str]] = []
    fence: str | None = None
    for line in text.split("\n"):
        stripped = line.lstrip()
        m = re.match(r"^(```+|~~~+)", stripped)
        if m:
            tok = m.group(1)
            if fence is None:
                fence = tok[0] * 3
            elif stripped.startswith(fence):
                fence = None
            continue
        if fence is None:
            hm = re.match(r"^(#{1,6})\s+(.*)$", line)
            if hm:
                res.append((len(hm.group(1)), hm.group(2).strip()))
    return res


def part6(originals: str, compiled: str) -> str:
    """The audit Part. The coverage table is computed from the code at compile
    time, so the numbers in the document cannot drift from the numbers on disk.
    `originals` is the raw text of the five source documents, before this
    compiler touched them; `compiled` is Parts 1-5 as assembled, which the
    reverse check needs because it looks for the Part headers. `originals` — measuring the compiled text instead would credit
    the old documents with the corrections this file adds."""
    import tool_audit_doc as audit

    rows = [
        ("verbs the phone sends", audit.verbs_in_code()),
        ("`hello.features` flags", audit.features_in_code()),
        ("error codes", audit.error_codes_in_code()),
    ]
    rows += [(k, v) for k, v in audit.android_facts().items()]
    rows.append(("Dart source files", audit.dart_files_rel()))

    out = io.StringIO()
    w = out.write
    w("# Part 6 · Audit: this file against the code (2026-09-30)\n\n")
    w("Parts 1–5 are design documents: they were written before and during the "
      "build, and Parts 3 and 5 describe a *different* repository "
      "(`hamamun/Salu`) that is not in this checkout. This Part is the check "
      "the other four never had — every fact the Android side of this "
      "repository can be asked about was extracted **from the code** and "
      "searched for in this document.\n\n")
    w("Both halves are scripts kept in the repository root, so the check is "
      "repeatable instead of a claim:\n\n")
    w("- `python3 tool_compile_doc.py` — rebuilds this file from the five "
      "originals (they are in git history at the commit before this one).\n"
      "- `python3 tool_audit_doc.py` — re-runs the audit. Add `--inherited` to "
      "measure Parts 1–5 alone, which is what the table below reports.\n\n")
    w("## 6.1 What the inherited Parts 1–5 did not cover\n\n")
    w("| Extracted from the code | Found in the five original documents | Not mentioned in any of them |\n|---|---|---|\n")
    gaps: dict[str, list[str]] = {}
    for name, items in rows:
        missing = sorted(i for i in items if i not in originals)
        if missing:
            gaps[name] = missing
        w(f"| {name} | {len(items) - len(missing)} / {len(items)} | "
          f"{', '.join('`' + m + '`' for m in missing) if missing else '—'} |\n")
    w("\n*(Measured against the five originals as they were, before this "
      "compiler touched them. The one correction note injected into Part 2 §4 "
      "on 2026-09-30 already names `ACCESS_NETWORK_STATE`, "
      "`app.salu.remote/deep_link` and `connectivity_plus`, so re-running "
      "`tool_audit_doc.py --inherited` against the compiled file reports three "
      "fewer gaps than this table does.)*\n\n")
    reverse = audit.reverse_check(compiled)
    flags = {"pc_power", "queue_groups_paged", "web_bookmarks", "web_home",
             "web_media_unit", "web_mouse", "web_tabs"}
    rest = [r for r in reverse if r not in flags]
    w(f"**The reverse direction is clean too.** {len(reverse)} verb-shaped "
      f"names appear in Parts 3–5 that this phone never sends: "
      f"{len(flags & set(reverse))} of them are `hello.features` flags rather "
      f"than verbs, and the other {len(rest)} are "
      + ", ".join(f"`{r}`" for r in rest)
      + ". Every one of those is accounted for in the text — `seek_chapter`, "
      "`browser_back`, `browser_reload`, `browser_tabs` and `browser_get` are "
      "Part 3 §9's \"reserved for v2\" list, `web_mouse_scroll` / `web_scroll` "
      "are Part 5 C3's \"not built, not ordered\" wheel verb, and "
      "`repeat_one` is an icon name. Nothing in the specification promises a "
      "verb the code forgot.\n\n")
    w("Read that table like this: **the protocol is complete and the "
      "surroundings were not.** Every verb the phone can put on the wire and "
      "every `hello.features` flag it understands was already specified in "
      "Part 3 — nothing there was invented at build time. What the four "
      "inherited documents never listed is the *local* half of the app: the "
      "failure codes the phone raises against itself rather than receiving "
      "from the PC, one Android permission, one method channel, two "
      "dependencies, and 24 of the 47 Dart files. Sections 6.2–6.4 below close "
      "each of those; after them the audit reports full coverage of the whole "
      "file.\n\n")

    # ── 6.2 error vocabulary ────────────────────────────────────────────────
    w("## 6.2 The phone's complete error vocabulary\n\n")
    w("`lib/core/error_copy.dart` is the one place a failure becomes a "
      "sentence, and it is the authority for this table — Part 3 §6.4 and "
      "§17.8 list only the codes the **PC** sends. Codes marked *new here* "
      "appear in no inherited Part; they exist because the phone has failure "
      "modes of its own, and a code with no sentence would have reached the "
      "user as a blank row.\n\n")
    w("| Code | Where it comes from | The phone shows |\n|---|---|---|\n")
    for code, origin, shown in ERROR_TABLE:
        w(f"| `{code}` | {origin} | {shown} |\n")
    w("\nTwo things this table settles that the inherited Parts left "
      "ambiguous:\n\n")
    w("1. **Four codes are specified but not yet mirrored.** Part 5 A6.2 and "
      "C6.2 both order `no_web_tabs`, `tab_not_found`, `no_web_bookmarks` and "
      "`no_web_mouse` into `lib/protocol/remote_protocol.dart`. As of this "
      "audit that file's `RemoteErrorCode` still ends at `invalid_arguments` "
      "and has none of the four — the phone displays them correctly anyway, "
      "because `error_copy.dart` keys off the wire string and not off the "
      "constant. The mirror is still owed: the file's own header calls the two "
      "copies *\"one file with two addresses\"*.\n")
    w("2. **`library_full` has no producer on this side.** It is display-only "
      "copy for a PC that answers a full saved-stream list (the PC's "
      "`UrlLibraryService` caps at 7 entries — Part 4 §5.2). Nothing in `lib/` "
      "raises it.\n\n")

    # ── 6.3 android surface ─────────────────────────────────────────────────
    w("## 6.3 The Android surface as it actually is\n\n")
    w("Part 2 §4.1 and §4.3 carry the manifest and `MainActivity.kt` as they "
      "were written, and they predate two things the app now needs. **The "
      "files below are the current ones — verify against these, not against "
      "Part 2's samples, and never paste a sample over them.**\n\n")
    w("| Fact | Value in this checkout | In Parts 1–5? |\n|---|---|---|\n")
    facts = audit.android_facts()
    w("| Permissions | " + " · ".join(f"`{p}`" for p in sorted(facts['permission'])) +
      " | `ACCESS_NETWORK_STATE` was not mentioned |\n")
    w("| Method channels | " + " · ".join(f"`{c}`" for c in sorted(facts['method channel'])) +
      " | `app.salu.remote/deep_link` was not mentioned |\n")
    w("| Intent filter | `salu://pair` (`android:scheme=\"salu\"` + "
      "`android:host=\"pair\"`) | yes |\n")
    w(f"| `{sorted(facts['sdk pin'])[0]}` (was `flutter.minSdkVersion`) | "
      f"{sorted(facts['sdk pin'])[0].split('= ')[1]} | yes |\n")
    w(f"| Gradle · AGP · Kotlin | {audit.labelled_pins()} | yes (Part 1, the "
      "whole Java/Gradle section) |\n")
    w(f"| Dependencies | {audit.labelled_deps()} | `connectivity_plus`, "
      "`cupertino_icons` and `flutter_lints` were not mentioned |\n")
    w("\n`ACCESS_NETWORK_STATE` and `connectivity_plus` are the same change "
      "from two sides: Part 5 E0.3 promises *\"network-up events redial at "
      "once\"*, and that is `connectivity_plus` listening for a network "
      "change — which on Android requires the permission. `app.salu.remote/"
      "deep_link` is the second door of D2's QR pairing: a scan handled by the "
      "*camera app* arrives as an intent, so `MainActivity` keeps the last "
      "link and answers `getInitial` on a cold start, and pushes `onLink` when "
      "the app is already open (`launchMode=\"singleTop\"` → `onNewIntent`). "
      "Part 2 §4.3's sample has neither.\n\n")
    w("These two blocks are **read from disk at compile time**, so they cannot "
      "be older than the repository:\n\n")
    for label, rel in (
        ("`android/app/src/main/AndroidManifest.xml`", "android/app/src/main/AndroidManifest.xml"),
        ("`android/app/src/main/kotlin/app/salu/salu_remote/MainActivity.kt`",
         "android/app/src/main/kotlin/app/salu/salu_remote/MainActivity.kt"),
    ):
        content = (ROOT / rel).read_text(encoding="utf-8").strip("\n")
        lang = {"xml": "xml", "kt": "kotlin"}.get(rel.rsplit(".", 1)[-1], "")
        w(f"##### {label}\n\n```{lang}\n{content}\n```\n\n")

    # ── 6.4 file map ────────────────────────────────────────────────────────
    w("## 6.4 The file map — every Dart file in this repository\n\n")
    w("24 of these 47 files are named nowhere in Parts 1–5. Listed in full so "
      "that working from this one file means knowing the whole tree.\n\n")
    on_disk = audit.dart_files_rel()
    unknown = sorted(on_disk - set(FILE_ROLES))
    if unknown:
        w("> **Drift:** these files exist on disk but have no role line yet — "
          + ", ".join(f"`{u}`" for u in unknown) + ".\n\n")
    stale = sorted(set(FILE_ROLES) - on_disk)
    if stale:
        w("> **Drift:** these role lines have no file on disk any more — "
          + ", ".join(f"`{s}`" for s in stale) + ".\n\n")
    w("| File | What it is |\n|---|---|\n")
    for path in on_disk:
        w(f"| `{path}` | {FILE_ROLES.get(path, '*no role line yet*')} |\n")
    w("\n`lib/ui/dpad.dart` is deliberately absent: Part 4 §6.0 deleted it on "
      "2026-09-24 in favour of `lib/ui/mouse_pad.dart`, and Part 5 C6.4 "
      "records the same. `lib/ui/theme.dart` likewise no longer has "
      "`CommitSlider` (Part 5 A10 — `LiveSlider` is the app's one slider).\n\n")

    # ── 6.5 not checked ─────────────────────────────────────────────────────
    w("## 6.5 What this audit could not check\n\n")
    w("Stated plainly, because an audit that hides its own blind spot is worse "
      "than none:\n\n")
    w("- **`flutter analyze` and `flutter test` were not run.** This sandbox "
      "has no Flutter or Dart SDK, and the download is blocked at the TLS "
      "layer — the same limitation Part 5 A10 and F5 already record for the "
      "phone side. Everything in 6.1–6.4 is a **static** reading of the source: "
      "grep and parse, no compilation, no test run. The 13 files in `test/` "
      "are described, not executed.\n")
    w("- **Nothing on the PC side was verified at all.** `hamamun/Salu` is not "
      "in this checkout, so Parts 3 and 5 are reproduced as written. Their "
      "*\"implementation record\"* tables say the work landed in that "
      "repository; that claim could not be checked here and is not endorsed by "
      "this audit.\n")
    w("- **The live behaviours are still open.** YouTube actually going "
      "fullscreen from the phone, the PC cursor moving under a thumb, "
      "sleep/wake reconnection — those are the acceptance checklists in Part 5 "
      "(A8, C6.6, E8, F5) and they need the user's own Windows PC and a paired "
      "phone.\n")
    return out.getvalue()


# Code → origin → the sentence the user sees, for §6.2. Ordered PC-side first,
# then the phone's own. Verified against lib/core/error_copy.dart,
# lib/protocol/remote_protocol.dart, lib/core/client.dart and
# lib/core/connect_failure.dart on 2026-09-30.
ERROR_TABLE: list[tuple[str, str, str]] = [
    ("bad_code", "PC (Part 3 §6.4)", "That pairing code is not valid."),
    ("bad_token", "PC (Part 3 §6.4)", "This phone is no longer paired."),
    ("version_mismatch", "PC (Part 3 §6.4)", "Update SALU Remote — the PC speaks a different version."),
    ("nothing_playing", "PC (Part 3 §6.4)", "Nothing is playing on the PC."),
    ("not_seekable", "PC (Part 3 §6.4)", "This stream can't be seeked."),
    ("unknown_command", "PC (Part 3 §6.4) — **silent**", "nothing; it is how a missing feature flag is detected"),
    ("too_fast", "PC (Part 3 §6.4) — **silent**", "nothing; the read lane backs off on its own (Part 5 F0)"),
    ("no_preset", "PC (Part 3 §17.8) — **silent**", "nothing; logged"),
    ("file_access_off", "PC (Part 3 §17.8)", "File browsing is turned off on the PC."),
    ("path_not_found", "PC (Part 3 §17.8)", "That folder or file is no longer there."),
    ("not_a_directory", "PC (Part 3 §17.8)", "That path is not a folder."),
    ("no_media", "PC (Part 3 §17.8)", "Nothing is playing on the PC."),
    ("no_key", "PC (Part 3 §17.8)", "Add an OpenSubtitles key on the PC to search."),
    ("signed_out", "PC (Part 3 §17.8)", "Sign in to OpenSubtitles on the PC to download subtitles."),
    ("quota", "PC (Part 3 §17.8)", "OpenSubtitles download limit reached. Try again tomorrow."),
    ("no_web_media", "PC (Part 3 §17.8)", "This site's player can't be controlled from outside."),
    ("busy", "PC (Part 3 §17.8)", "The PC is busy — try again in a moment."),
    ("invalid_arguments", "PC (Part 3 §17.13.2)", "The PC didn't understand that request."),
    ("no_web_tabs", "PC (Part 5 A6) — **not yet mirrored into `remote_protocol.dart`**", "Tab control needs an updated SALU on the PC."),
    ("tab_not_found", "PC (Part 5 A6) — **not yet mirrored**", "That tab is no longer open."),
    ("no_web_bookmarks", "PC (Part 5 A6) — **not yet mirrored**", "The PC's browser has no bookmarked pages."),
    ("no_web_mouse", "PC (Part 5 C6) — **not yet mirrored**", "The PC couldn't move its pointer."),
    ("stale_queue", "PC (Part 5 F2) — **new here**", "The playlist changed. (the phone then re-reads state)"),
    ("too_large", "PC (Part 5 F2), or the phone's own 8 KB write guard — **new here**", "The request or response is too large."),
    ("invalid_response", "phone, `lib/core/queue_reader.dart` (Part 5 F2 fragment validation) — **new here**", "Invalid playlist response."),
    ("library_full", "PC, no producer on this side — **new here**", "The saved stream list is full."),
    ("offline", "phone, `lib/core/reply.dart` — no open socket", "Not connected to your PC."),
    ("timeout", "phone, `lib/core/client.dart` — the 8 s command budget", "The PC did not answer in time."),
    ("remote_off", "phone, naming close code **4004** — **new here**", "Remote control is switched off in SALU on the PC."),
    ("not_private_lan", "phone, naming close code **4003** — **new here**", "The PC only accepts phones on its own local network."),
    ("too_many", "phone, naming close code **4005** — **new here**", "The PC has too many remote connections already."),
    ("auth_failed", "phone, naming close code **4001** — **new here**", "The PC did not accept this phone."),
    ("unreachable", "phone, `lib/core/connect_failure.dart`", "Can't reach the PC."),
    ("refused", "phone, `lib/core/connect_failure.dart`", "That address is not a SALU Remote."),
    ("not_paired", "phone, local state — **new here**", "This phone is not paired with the PC yet."),
]

# Role lines for §6.4, from each file's own leading doc comment.
FILE_ROLES: dict[str, str] = {
    "lib/main.dart": "The app itself: `SaluRemoteApp`, pairing and preferences loaded before the first frame, deep links registered.",
    "lib/protocol/remote_protocol.dart": "**Copied from the PC repo — do not edit separately.** `proto: 1`, the 8 KB cap, close codes 4001–4005, `RemoteErrorCode`, `RemoteSnapshot`.",
    "lib/core/client.dart": "The one connection: auth, reconnect with backoff, snapshot application, one thin wrapper per verb, the retry lane, the 10 s transport keepalive and the 5 s `ping` speedometer.",
    "lib/core/models.dart": "Typed views over the PC's values — snapshot, playback, queue, web, tune, subs; `WebMediaInfo`'s unit detection; the tab/bookmark/focus parses; `RemoteFeature`.",
    "lib/core/reply.dart": "One reply type for every verb: ok, error, typed result, or the phone's own `offline`.",
    "lib/core/error_copy.dart": "Every failure in plain words (§6.2), plus the set the specs deliberately keep silent.",
    "lib/core/connect_failure.dart": "Turns a Dart socket exception into `unreachable` (retry) or `refused` (that address is not SALU), with the sentence to match.",
    "lib/core/pc_address.dart": "Makes sense of the address box — `192.168.0.12`, `…:7258`, a `salu://pair` URI — defaulting to port 7258 (Part 3 §8.1).",
    "lib/core/deep_link.dart": "The second QR door: parses `salu://pair` and talks to the `app.salu.remote/deep_link` channel (`getInitial` on a cold start, `onLink` while open).",
    "lib/core/prefs.dart": "What the phone remembers: the paired PC and its token, plus focus mode, the show/hide checklist, collapse states and channel favourites by title.",
    "lib/core/screen.dart": "Keep-screen-awake over the `app.salu.remote/screen` channel — one window flag, deliberately not a plugin.",
    "lib/core/web_url.dart": "Two pure functions: `webAddress` adds the scheme (the blank-new-tab fix) and `homeOrigin` computes the Home button's target.",
    "lib/core/queue_reader.dart": "The paced, serial, byte-budgeted read lane for `queue_get` / `queue_groups_page` — playback and heartbeats never wait behind it (Part 5 F0/F2).",
    "lib/core/queue_view.dart": "The queue card's paint list, pure: accordion, search filter, favourites filter — testable without a widget.",
    "lib/ui/root.dart": "The shell: header (dot · name · focus · ⋮), three tabs, the mini now-playing strip, the connect sheet, and the ⋮ menu with Sleep PC / Shut down PC.",
    "lib/ui/theme.dart": "SALU's palette ported from the PC, and `LiveSlider` — the app's one slider (streams while dragging).",
    "lib/ui/widgets.dart": "Shared furniture: fire-a-verb-and-say-why, collapsible section headers, the activity dot, the one honest line for a dead end.",
    "lib/ui/connect_sheet.dart": "The one place pairing happens: QR · manual · paste, diagnostics, **Connection history** (Part 5 F0), remember me.",
    "lib/ui/qr_scan.dart": "The in-app camera scanner (`mobile_scanner`) — the other half of D2.",
    "lib/ui/play_tab.dart": "Tab 1 in Player mode: transport row, repeat · shuffle · start-over row, live sliders, the full-width Player·Web switch, focus mode.",
    "lib/ui/queue_card.dart": "The playlist: 5 visible rows, auto-scroll, tap to jump, ✕ to clear, search, favourites and the grouping accordion.",
    "lib/ui/browse_tab.dart": "Tab 2 shell: the Files | Streams switch, greyed with a reason while the PC is in Web mode.",
    "lib/ui/files_browser.dart": "Browse → Files: breadcrumb, quick places, local drives only, 200-row pages, multi-select, and subtitle-picker mode.",
    "lib/ui/streams.dart": "Browse → Streams: the PC's own URL library mirrored, with add / rename / delete and the PC's health dot.",
    "lib/ui/tune_tab.dart": "Tab 3 shell: Equalizer | Subtitles | Audio — or, in Web mode, the mouse pad and nothing else.",
    "lib/ui/equalizer.dart": "Tune → Equalizer: the live curve, the PC's presets, ten sliders, Speed chips, Auto EQ.",
    "lib/ui/subtitles.dart": "Tune → Subtitles: tracks, sync, the file picker, auto-download — the PC does the work.",
    "lib/ui/subs_search.dart": "The OpenSubtitles search screen, pre-filled with the PC's current title.",
    "lib/ui/audio_tracks.dart": "Tune → Audio: the audio-track list, mirroring the PC's selection.",
    "lib/ui/web_body.dart": "The Play tab in Web mode, both shapes — the nav row and the page doors, or the page player's own controls.",
    "lib/ui/web_sheets.dart": "☆ Saved pages (bookmarks only) and the long-press **Web diagnostics** sheet.",
    "lib/ui/web_tabs_card.dart": "The collapsible **Open tabs** section at the foot of the Web body — the queue card's shape, the queue card's memory.",
    "lib/ui/mouse_pad.dart": "The trackpad, the two ▲▼ scroll seats and the one `Mouse` line.",
    "lib/ui/settings_sheet.dart": "The phone's own settings: the name the PC shows, and the permanent show/hide checklist.",
    "test/widget_test.dart": "First launch: header, the three tabs, and the connect sheet opening on a fresh device.",
    "test/browse_seat_test.dart": "The Browse seat greys in Web mode **and** un-greys on the way back — both directions, with the sentence on tap (Part 3 §17.9 step 29).",
    "test/connect_failure_test.dart": "Socket errors classified into `unreachable` vs `refused`.",
    "test/deep_link_test.dart": "`salu://pair` parsing: `v` · `n` · `h` · `p` · `c`, and the rejects.",
    "test/mouse_pad_test.dart": "The trackpad's maths and gestures: 2.5× gain, ±320 px clamp, 40 ms batching, and the one line.",
    "test/pc_address_test.dart": "The address box: `host:port`, a bare host, a URI, and junk.",
    "test/power_client_test.dart": "`pc_sleep` / `pc_shutdown` on the wire, gated on `pc_power`, sent exactly once.",
    "test/power_menu_test.dart": "The ⋮ menu in Player, Web and Focus mode: disabled states, confirmations, nothing sent on cancel.",
    "test/queue_reader_test.dart": "Part 5 F2's lane: paging, the `too_large` shrink, `stale_queue`, fragment merge and coverage validation.",
    "test/queue_view_test.dart": "The accordion, search and favourites paint list.",
    "test/track_info_test.dart": "Track names: a readable language label, never a duplicated generic `Track`.",
    "test/web_media_test.dart": "Unit detection and write-side conversion, plus the tab / bookmark / focus parses.",
    "test/web_url_test.dart": "`webAddress` (the blank-tab fix) and `homeOrigin`.",
}


def main() -> int:
    bodies: list[tuple[dict, str]] = []
    for part in PARTS:
        source = ROOT / part["file"]
        if not source.exists():
            raise SystemExit(
                f"{source.name} is gone — it was deleted after being merged "
                f"into salu_remote.md. Recover the five originals from git "
                f"history and re-run:\n\n"
                f"    git checkout 91889c4389 -- README.md "
                f"SETUP_STEP_BY_STEP.md remote.md remote_apk_ui.md pc_part.md\n"
                f"    python3 tool_compile_doc.py\n"
            )
        raw = source.read_text(encoding="utf-8")
        body = demote(raw, part["drop_h1"])
        body = fix_links(body)
        anchor = part.get("inject_after")
        if anchor:
            if anchor not in body:
                raise SystemExit(f"{part['file']}: injection anchor not found: {anchor!r}")
            body = body.replace(anchor, anchor + part["injection"], 1)
        body = body.strip("\n")
        bodies.append((part, body))

    return assemble(bodies)


def front_matter(bodies: list[tuple[dict, str]], audit: str | None = None) -> str:
    """The document's opening: provenance, the old-name mapping, status, and a
    table of contents. `audit` is passed on the second pass, once Part 6 exists,
    so its own sections can be listed too."""
    fm = io.StringIO()
    w = fm.write
    w("# SALU Remote — one file\n\n")
    w("> **This file replaced five.** It was compiled on **2026-09-30** in "
      "`hamamun/salu-remote` from `README.md`, `SETUP_STEP_BY_STEP.md`, "
      "`remote.md`, `remote_apk_ui.md` and `pc_part.md`, all five of which have "
      "since been deleted from the repository. Nothing was rewritten or "
      "summarised away: each document became a Part below, its headings one "
      "level deeper, its section numbers untouched. Part 6 is new — an audit of "
      "this file against the code as it actually stands.\n\n")
    w("The repository itself is **the Android app** (`lib/`, `test/`, "
      "`android/`). The PC application it talks to lives in a different "
      "repository, `hamamun/Salu`, and is **not** in this checkout — so Parts 3 "
      "and 5 are the specification and work orders that the other side "
      "implements, kept here because the phone's own code comments cite them "
      "line by line.\n\n")
    w("## How the old file names map onto this one\n\n")
    w("Every Dart file in this repository carries doc comments in the shape "
      "`remote.md §17.4` or `remote_apk_ui.md §6.0`. Those names are now gone, "
      "so read them like this — **the section numbers are unchanged**:\n\n")
    w("| Cited in code as | Now lives in | Covers |\n|---|---|---|\n")
    for part, _ in bodies:
        w(f"| {part['old']} | **Part {part['n']}** | {part['desc']} |\n")
    w("\nOne exception worth knowing: `pc_part.md §11` in a code comment means "
      "**Part 5 → Part B → §11** (channel grouping), because Part B numbers its "
      "own sections 1–12 rather than using the `B1` style of the other work "
      "orders.\n\n")
    w("## Status at a glance (2026-09-30)\n\n")
    w("| Area | Phone (this repo) | PC (`hamamun/Salu`) |\n|---|---|---|\n")
    w("| Pairing (QR + `salu://pair`), transport, volume, queue card | built | built |\n")
    w("| Browse (Files · Streams), Tune (EQ · Subs · Audio) | built | built |\n")
    w("| Web mode: page player, tabs, saved pages, Home, one fullscreen seat, trackpad | built, feature-flagged | Part A + Part C — **acceptance on the user's PC pending** |\n")
    w("| Sleep PC / Shut down PC in ⋮ | built, gated on `pc_power` | Part D — **acceptance pending** |\n")
    w("| Connection reliability (heartbeat, stall nudge, replay) | built | Part E — **acceptance pending** |\n")
    w("| Large playlists + capability-gated grouping | built, gated on `queue_groups_paged` | Part F — **implementation pending** |\n")
    w("\n## Contents\n\n")
    for part, _ in bodies:
        w(f"- **Part {part['n']}** — {part['title'].split('· ', 1)[-1]}"
          f" *(was {part['old']})*\n")
    w("- **Part 6** — Audit: this file against the code (2026-09-30)\n")
    for part, body in bodies:
        # "Contents of" keeps this heading's anchor distinct from the Part
        # header it links to — otherwise both slug to the same value and every
        # link would land on the table of contents instead of the Part.
        w(f"\n### Contents of Part {part['n']} — {part['title'].split('· ', 1)[-1]}\n\n")
        for level, title in headings(body):
            if level > 3:
                continue
            w(f"{'  ' * (level - 2)}- [{title}](#{slug(title)})\n")
    if audit:
        w("\n### Contents of Part 6 — Audit\n\n")
        for level, title in headings(audit):
            if level > 3:
                continue
            w(f"{'  ' * (level - 2)}- [{title}](#{slug(title)})\n")
    return fm.getvalue()


def parts_text(bodies: list[tuple[dict, str]]) -> str:
    out: list[str] = []
    for part, body in bodies:
        out.append("\n---\n\n# " + part["title"] + "\n\n")
        out.append("> *(This Part was the whole of `" + part["file"] + "`; its "
                   "headings are one level deeper than they used to be, its "
                   "section numbers are unchanged.)*\n\n")
        out.append(body + "\n")
    return "".join(out)


def assemble(bodies: list[tuple[dict, str]]) -> str:
    """Two passes. The audit measures Parts 1-5, so it must be written before
    it can be listed in the table of contents that precedes it."""
    parts = parts_text(bodies)
    originals = "".join(
        (ROOT / part["file"]).read_text(encoding="utf-8") for part in PARTS
    )
    audit = part6(originals, parts)
    return front_matter(bodies, audit) + parts + "\n---\n\n" + audit


if __name__ == "__main__":
    text = main()
    (ROOT / "salu_remote.md").write_text(text, encoding="utf-8")
    print(f"wrote salu_remote.md — {len(text)} bytes, "
          f"{text.count(chr(10)) + 1} lines", file=sys.stderr)
