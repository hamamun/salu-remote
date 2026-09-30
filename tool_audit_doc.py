#!/usr/bin/env python3
"""Audit: does salu_remote.md actually cover everything the code contains?

Scans the Android side of this repository (lib/, test/, android/, pubspec.yaml)
for the things a specification must not be silent about — every verb the phone
can send, every `hello.features` flag it understands, every error code it can
put into words, every source file, every permission, channel and version pin —
and reports which of them the compiled document does not mention.

Run:  python3 tool_audit_doc.py [--quiet]
Exit: 0 when the document covers everything, 1 when something is missing.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DOC = "salu_remote.md"


def dart_files() -> list[Path]:
    return sorted([*ROOT.glob("lib/**/*.dart"), *ROOT.glob("test/*.dart")])


def dart_files_rel() -> set[str]:
    return {str(p.relative_to(ROOT)) for p in dart_files()}


def labelled_pins() -> str:
    """The three build pins, named — the bare numbers sort into a meaningless
    order (`2.4.0` before `9.3.1`)."""
    wrapper = (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
    settings = (ROOT / "android/settings.gradle.kts").read_text(encoding="utf-8")
    g = re.findall(r"gradle-([0-9.]+)-all", wrapper)
    a = re.findall(r'"com.android.application"\) version "([0-9.]+)"', settings)
    k = re.findall(r'"org.jetbrains.kotlin.android"\) version "([0-9.]+)"', settings)
    return (f"Gradle `{g[0]}` · AGP `{a[0]}` · Kotlin `{k[0]}`"
            if g and a and k else "Gradle/AGP/Kotlin")


def labelled_deps() -> str:
    """`pubspec.yaml`'s real entries. The bare regex also catches `sdk: ^3.13.3`
    under `environment:`, which is the Dart SDK constraint, not a package."""
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    out = []
    for name, ver in re.findall(r"(?m)^  ([a-z_0-9]+): \^?([\d.]+)\s*$", pubspec):
        out.append(f"`{name}: ^{ver}`" if name != "sdk" else f"Dart SDK `^{ver}`")
    return " · ".join(out)


def verbs_in_code() -> set[str]:
    """Every verb string the phone can put on the wire."""
    found: set[str] = set()
    src = (ROOT / "lib/core/client.dart").read_text(encoding="utf-8")
    found |= set(re.findall(r"send\(\s*'([a-z_]+)'", src))
    found |= set(re.findall(r"'verb':\s*'([a-z_]+)'", src))
    found |= set(re.findall(r"send\(\s*'([a-z_]+)'", (ROOT / "lib/core/queue_reader.dart").read_text(encoding="utf-8")))
    found |= set(re.findall(r"_read\(\s*'([a-z_]+)'", (ROOT / "lib/core/queue_reader.dart").read_text(encoding="utf-8")))
    return found


def features_in_code() -> set[str]:
    src = (ROOT / "lib/core/models.dart").read_text(encoding="utf-8")
    body = src[src.index("abstract final class RemoteFeature"):]
    return set(re.findall(r"static const String \w+ = '([a-z_0-9]+)'", body))


def error_codes_in_code() -> set[str]:
    codes: set[str] = set()
    copy = (ROOT / "lib/core/error_copy.dart").read_text(encoding="utf-8")
    codes |= set(re.findall(r"case '([a-z_0-9]+)':", copy))
    proto = (ROOT / "lib/protocol/remote_protocol.dart").read_text(encoding="utf-8")
    codes |= set(re.findall(r"static const String \w+ = '([a-z_0-9]+)'", proto))
    client = (ROOT / "lib/core/client.dart").read_text(encoding="utf-8")
    codes |= set(re.findall(r"code: '([a-z_0-9]+)'", client))
    return codes


def android_facts() -> dict[str, set[str]]:
    manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    activity = (ROOT / "android/app/src/main/kotlin/app/salu/salu_remote/MainActivity.kt").read_text(encoding="utf-8")
    gradle_app = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    settings = (ROOT / "android/settings.gradle.kts").read_text(encoding="utf-8")
    wrapper = (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    return {
        "permission": set(re.findall(r'uses-permission android:name="android.permission.([A-Z_]+)"', manifest)),
        "method channel": set(re.findall(r'"(app\.salu\.remote/[a-z_]+)"', activity)),
        "scheme/host": set(re.findall(r'android:(scheme|host)="([a-z]+)"', manifest) and {"salu://pair"}),
        "sdk pin": {f"minSdk = {m}" for m in re.findall(r"minSdk = (\d+)", gradle_app)},
        "gradle pin": set(re.findall(r"gradle-([0-9.]+)-all", wrapper)) |
                      set(re.findall(r'"com.android.application"\) version "([0-9.]+)"', settings)) |
                      set(re.findall(r'"org.jetbrains.kotlin.android"\) version "([0-9.]+)"', settings)),
        "dependency": _deps(),
    }


def _deps() -> set[str]:
    """Package names from `pubspec.yaml`. `sdk: ^3.13.3` under `environment:` is
    the Dart SDK constraint rather than a package, so it is checked by its
    version string instead of the meaningless word `sdk`."""
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    found = set(re.findall(r"(?m)^  ([a-z_0-9]+): \^", pubspec))
    if "sdk" in found:
        found.discard("sdk")
        found |= set(re.findall(r"(?m)^  sdk: (\^[\d.]+)", pubspec))
    return found


VERB_SHAPE = re.compile(
    r"^(web_|fs_|queue_|eq_|sub|library_|browser_|pc_|mode_set|fullscreen_|open_url|"
    r"seek_|set_volume|volume_step|mute_|shuffle_|repeat_|take_control|restart$|auto_eq|"
    r"speed_set|tune_get|state_get|ping$|play_pause|stop$|next$|previous$)"
)


def reverse_check(doc: str) -> list[str]:
    """The other direction: verb-shaped names the specification mentions but the
    phone never sends. Feature flags, icon names and the verbs Parts 3/5 mark
    'reserved' or 'not built' land here too, so this is a list to read, not a
    failure count — an unexplained entry would be a verb the spec promises and
    the code forgot."""
    i3 = doc.index("\n# Part 3 ·")   # line-start H1, not Part 2's inner "Part 3"
    i6 = doc.find("\n# Part 6 ·")     # absent while Part 6 is still being built
    toks = set(re.findall(r"`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`",
                          doc[i3:i6 if i6 > 0 else len(doc)]))
    sent = verbs_in_code()
    return sorted(t for t in toks if t not in sent and VERB_SHAPE.match(t))


def main() -> int:
    doc = (ROOT / DOC).read_text(encoding="utf-8")
    quiet = "--quiet" in sys.argv
    if "--inherited" in sys.argv:
        # Measure the four inherited documents only. Part 6 is the closure of
        # what it finds, so including it would make the check circular.
        doc = doc.split("# Part 6 · Audit", 1)[0]
        print("measuring Parts 1-5 as they appear in this file (--inherited);\n"
              "note this includes the correction note added to Part 2 \u00a74 on\n"
              "2026-09-30, so it reports fewer gaps than the originals did\n")

    groups: dict[str, set[str]] = {
        "verbs the phone sends": verbs_in_code(),
        "`hello.features` flags": features_in_code(),
        "error codes": error_codes_in_code(),
    }
    groups.update(android_facts())
    groups["Dart source files"] = dart_files_rel()

    bad = 0
    for name, items in groups.items():
        missing = sorted(i for i in items if i not in doc)
        if not quiet or missing:
            print(f"{name:26} {len(items) - len(missing):3}/{len(items):3} covered"
                  + ("" if not missing else f"   MISSING: {', '.join(missing)}"))
        bad += len(missing)
    reverse = reverse_check(doc)
    print(f"\nreverse check: {len(reverse)} verb-shaped name(s) in Parts 3-5 that "
          f"the phone never sends")
    for t in reverse:
        print(f"    {t}")

    print(f"\n{'DOCUMENT IS COMPLETE' if not bad else str(bad) + ' ITEM(S) NOT COVERED'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
