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

Gradle in this checkout runs on **Java 17–23**. If your default `java` is 24/25, start with
[Troubleshooting § Java/Gradle incompatibility](#build-fails-gradle-build-failed-due-to-javagradle-incompatibility-java-2503).

1. Open this repository as a Flutter project.
2. Connect an Android phone with USB debugging enabled.
3. From the repository root run `flutter pub get` once.
4. Select the phone and press **Run**.
5. Follow [`SETUP_STEP_BY_STEP.md`](SETUP_STEP_BY_STEP.md) to pair it with SALU.

`remote.md` is the PC-side protocol/implementation specification. `remote_apk_ui.md` is
the Android interface specification. They are design and implementation references, not
additional setup commands.

## Troubleshooting

### Error: `No Windows desktop project configured` when pressing Run

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

### Warnings: `A restricted method in java.lang.System has been called` during Gradle build

You will see this when running on your phone:

```
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning
```

**This is NOT an error — it's a harmless warning from Gradle 9 + Java 21/24.** Your app is still building. The first `assembleDebug` can take **5-15 minutes** downloading dependencies.

> **But check the tail of the log.** The warning is only harmless if the build *continues*. If the
> same log ends with `FAILURE: Build failed with an exception` / `Error: Gradle build failed due to
> Java/Gradle incompatibility`, the JDK is simply too new for the pinned Gradle — see the next
> section.

Just **wait**. After the warnings you should see:

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...
```

If the build hangs for >20 min or ends with a real error (red text `FAILURE` or `Exception`), copy the last 50 lines and send them.

**Fix already applied in this repo:** `android/settings.gradle.kts` now uses AGP `8.7.3` + Kotlin `2.1.0` and `gradle-wrapper.properties` uses Gradle `8.10.2` — the stable combo that removes the warning. That combo runs on **Java 17–23 only**; on Java 24/25 Gradle refuses to start (see below). After pulling:

```bash
cd salu-remote
flutter clean
flutter pub get
# delete old gradle cache if you had 9.3.1 before:
# On Windows: rmdir /s /q %USERPROFILE%\.gradle\wrapper\dists\gradle-9.3.1-all
flutter run -d ZPFU9LU8AEFISWPV
```

### Build fails: `Gradle build failed due to Java/Gradle incompatibility` (Java 25.0.3)

Same log as above, but the build stops. The giveaway is a `What went wrong:` block that contains
nothing but a Java version number:

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

**What it means:** the JDK that Flutter hands to Gradle is newer than this project's Gradle can run
on. Gradle prints the Java version as the entire error message — that is where the lone `25.0.3`
line comes from. Nothing in `lib/` or `android/` is broken, and it is **not** about the code.

This checkout pins Gradle `8.10.2`, so the JVM that *runs Gradle* must be Java 17–23:

| Java version that runs Gradle | Oldest Gradle that supports it |
|---|---|
| 17 | 7.3 |
| 21 | 8.5 |
| 23 | 8.10 |
| 24 | 8.14 |
| 25 | 9.1.0 |

Source: [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html#java).
Note this is about the JVM running Gradle, **not** about `compileOptions`/`jvmTarget = 17` in
`android/app/build.gradle.kts` — leave those at 17; they are the bytecode level of your app.

Also: `I/flutter … NtLifecycle->scheduledWakeUp tag:KeepAlive,length:Instance of 'BluetoothHelper',Instance of 'NtWatchWorker'`
is **not from SALU Remote** — nothing in `lib/` logs those tags. It is logcat noise from another app
on the phone, printed while Gradle was working. Ignore it.

#### Fix 1 — give Gradle a JDK it supports (recommended, ~2 minutes, no repo change)

1. Find out which Java Flutter uses for Gradle:

   ```bash
   flutter doctor --verbose
   ```

   Under **Android toolchain** read `Java binary at:` and `Java version`. Flutter looks for a JDK in
   this order: `jdk-folder` set by `flutter config` → **the JDK bundled with your newest Android
   Studio** → `JAVA_HOME` → `java` on `PATH`. Because the Studio-bundled JDK beats `JAVA_HOME`,
   changing `JAVA_HOME` alone often appears to do nothing — which is why we use `flutter config`.
   A Java 25 here means either that bundled JBR *is* 25 (current Android Studio releases ship a very
   new JBR) or that `JAVA_HOME` points at a JDK 25 you installed.

2. Find a JDK whose version is 17–21 and note its folder. Candidates, in PowerShell:

   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\java" -version   # newest Studio
   & "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java" -version  # per-user install
   dir "C:\Program Files\Eclipse Adoptium","C:\Program Files\Java","C:\Program Files\Microsoft" -ErrorAction SilentlyContinue
   ```

   If **every** candidate prints 24 or 25, install a second JDK side by side and leave `JAVA_HOME`
   and `PATH` untouched: [Temurin 21 LTS MSI](https://adoptium.net/temurin/releases/?version=21)
   → `C:\Program Files\Eclipse Adoptium\jdk-21…`. (It must be a JDK, not a JRE — `bin\javac.exe`
   has to exist, otherwise `javac -version` in the commands above fails.)

3. Tell Flutter to use it (this one line fixes the terminal and Android Studio's Run button at once,
   because Studio just runs the same `flutter … run` command):

   ```powershell
   flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.0.5.11-hotspot"
   # or, if the Studio-bundled JBR printed 17 or 21 in step 2:
   flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
   ```

   Prefer the standalone JDK over the Studio `jbr` if you have the choice: Android Studio updates
   replace its bundled JBR, and one day it will be Java 26 — a JDK you installed under your own path
   stays 21 and keeps this build working.

4. Set the same JDK inside Studio too, otherwise the Gradle tool window keeps showing red while the
   app itself builds fine: **File → Settings → Build, Execution, Deployment → Build Tools → Gradle →
   Gradle JDK** → pick `jbr-17` / `jbr-21` / *Specified JDK…* → **Apply**. (If you only ever press
   Run ▶ for Flutter you can skip this step.)

5. Kill the stuck daemons and build again:

   ```powershell
   flutter clean
   cd android
   .\gradlew.bat --stop
   cd ..
   flutter pub get
   flutter run -d ZPFU9LU8AEFISWPV
   ```

   In Android Studio instead: **File → Invalidate Caches… → Restart**, then **Run ▶**.

To confirm the fix, `flutter doctor --verbose` should now report a Java 17–23 version, and the log
should reach `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

#### Fix 2 — one setting for every tool on the machine

If you also build from other terminals/IDEs, put the JDK in your **user** Gradle properties —
`%USERPROFILE%\.gradle\gradle.properties` (create it if missing):

```properties
# the folder you picked in Fix 1, step 2 — forward slashes, ":" escaped
org.gradle.java.home=C\:/Program Files/Eclipse Adoptium/jdk-21.0.5.11-hotspot
```

Use forward slashes (`.properties` files treat `\` as an escape). Then run `.\gradlew.bat --stop`
once in `android/` and rebuild.

**Do not** add that line to `android/gradle.properties` — that file is committed, and a
`C:\Users\mamun\…` path in it breaks the build on every other machine.

#### Fix 3 — stay on JDK 25 by moving Gradle to 9.x (not recommended for this repo yet)

This is the option Flutter's own error message suggests first. It is a real upgrade, not a settings
change, and it is why this repo is on 8.10.2 in the first place:

- `android/gradle/wrapper/gradle-wrapper.properties` → Gradle **9.1.0–9.5.x** (`-bin.zip` is enough).
  Gradle 9.6+ drops the internal APIs AGP 8.x still uses, so AGP 8.7.3 stops working there.
- To go past 9.6 you must move to **AGP 9.x**, which brings built-in Kotlin, the new Variant API, and
  the `android.newDsl` / `android.builtInKotlin` flags in `android/gradle.properties`.
- Kotlin `2.1.0` predates Gradle 9, so the Kotlin Gradle plugin has to move up too.

Say the word and I will do Gradle + AGP + Kotlin as one commit for you to test on the phone — but
Fix 1 unblocks you today and is what everyone else on this repo should use.
