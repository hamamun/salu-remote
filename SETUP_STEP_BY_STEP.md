# SALU Remote — do this, in this order (no coding needed)

You will not write any code. You will **copy and paste** files, change **three lines** in
three files Android Studio created for you, and press **Run**.

Total time for Part 1–4: about 30–45 minutes the first time. Part 5 is 2 minutes.

Print this, or keep it open in the other monitor. Do not skip steps — every step is
verifiable before you move on.

---

## Part 0 · What we are making, in one paragraph

The SALU Remote app is a **separate app** (in your own Git repository) that lives on your
phone. It talks to SALU on your PC over your home Wi-Fi. The PC does all the thinking; the
phone is only a remote control. Right now the app knows how to **connect** and send
**play/pause, next, volume, mute** and so on — the SALU-looking interface, the QR scanner
and the other screens come next. You will be able to run it on your phone from Android
Studio after Part 4, and it will already control SALU after Part 5.

---

## Part 1 · Create the app skeleton and prove it runs (30 min)

### 1.1 Check your tools

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

### 1.2 Create the app folder on your computer

In the same terminal, go to where you keep projects. For example:

```bash
cd $HOME/Documents
flutter create --org app.salu --project-name salu_remote --platforms=android salu-remote
```

> **One line, and it matters.** Type it exactly. It creates a folder called `salu-remote`
> containing a working (empty) app called `salu_remote`.

If it prints `All done!`, you are good.

### 1.3 Run it on your phone (this proves everything works)

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

## Part 2 · Create your Git repository and put the skeleton in it

### 2.1 Make the repository

1. In a browser, go to **github.com** and log in.
2. Top-right `+` → **New repository**.
3. Name: `salu-remote`. Visibility: **Private** (or Public — your choice).
4. **Do not** tick "Add a README file". Press **Create repository**.
5. Leave the page open — you will upload into it.

### 2.2 Upload the skeleton — the easy way

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

## Part 3 · Paste my files into the repository (20 min)

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

## Part 4 · The three Android edits (10 min)

**Repository status:** these Android edits have already been applied to the current
`salu-remote` checkout. If you cloned or pulled this repository after that change, do not
paste the examples below over them again. Instead, verify that the files contain the
permissions, `minSdk = 24`, and `keepAwake` channel shown below, then continue to Part 5.

The examples remain here as a reference in case your local checkout is older. Do these
**on your computer**, in Android Studio — it underlines mistakes as you type, which the
web page cannot.

Open Android Studio → `File` → `Open…` → choose your `salu-remote` folder.

### 4.1 Give the app the internet and camera

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

### 4.2 Raise the minimum Android version

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

### 4.3 Keep the phone screen awake

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

## Part 5 · Run it and pair with SALU

### 5.1 Get dependencies and start the app on your phone

Because this checkout now uses `shared_preferences` to remember the pairing, run this once
in Android Studio's Terminal (from the repository root):

```bash
flutter pub get
```

Then pick your phone in the device dropdown at the top and press the green **Run ▶**.
First build is slow (2–5 minutes); after that, seconds.

You should see a dark screen titled **SALU Remote** with a **Connect to your PC** card and
two boxes: *PC address* and *Pairing code*.

### 5.2 Get the address and code from the PC

1. Start **SALU** on the PC and play something (or just leave it open).
2. Right-click on the picture → the little strip at the bottom-right → click **Remote**
   (the last icon).
3. The panel shows a line like `● Connected · Wi-Fi · 192.168.0.12 · 7258` and a code like
   `7K4M-QP2X`. The phone wants exactly those two things:
   - **PC address box** → `192.168.0.12:7258` (address, colon, port — as shown)
   - **Pairing code box** → `7K4M-QP2X` (dashes are fine, either way works)

### 5.3 Connect

Press **Connect** in the app. Within a second the top of the app changes from
*Connecting…* to a **green dot + Connected**, and the title becomes your PC's name.

Press **Play ▶**. The PC should pause. Press it again — it plays. Try the **10-second**
buttons, the **volume** slider, **Mute**, **Shuffle**, **Repeat**. Every button moves the PC
immediately, and the title/time in the app follows what the PC is doing.

**That is the whole loop working.** From now on, the app remembers your PC: next time you
open it, it connects by itself and goes straight to the controls.

---

## Part 6 · If something goes wrong

Look up your symptom, try the fix, and if it still fails send me the two things in §7.

| What you see | What it means / do |
|---|---|
| `flutter` is not recognised as a command | Flutter is not on your PATH. Close and reopen the terminal after installing; if it still fails, send me the output of `flutter doctor`. |
| Android Studio cannot see your phone | USB debugging still off, or the cable is charge-only. Turn on *Developer options → USB debugging*, unlock the phone screen, and accept the "Allow USB debugging?" prompt. |
| The app says *"Can't reach 192.168…"* | The phone and the PC are not on the same Wi-Fi, or SALU is not running, or **Remote** is switched off in SALU's Settings → General. |
| The app says *"That pairing code is not valid"* | The code changed. It rotates every time you close the PC's Remote panel. Reopen the panel and use the new code. |
| It connected on the PC but the phone keeps saying *Connecting…* | **Windows Firewall** is blocking SALU. In the PC's Remote panel there is a hint line with **Open firewall settings** after 90 seconds — allow SALU on **Private** networks. |
| Everything worked yesterday, dead today | The PC's IP changed (the router reassigned it). Open the PC's Remote panel, read the new address, and type it into the app's *PC address* box. |
| Red text in Android Studio under a file | Send me a screenshot of the file name and the red line. Do not "fix" it yourself. |
| The build fails with `Java heap space` | Tell me — I will give you the one-line change for `android/gradle.properties`. |
| Build stops with `Error: Gradle build failed due to Java/Gradle incompatibility` (and a bare version like `25.0.3` under `What went wrong:`) | Your Java is newer than the Gradle this repo pins (8.10.2 needs **Java 17–23**). Not a code problem — follow **README → “Build fails: Gradle build failed due to Java/Gradle incompatibility”**, Fix 1 (`flutter config --jdk-dir` → Android Studio's `jbr`, then `flutter clean`). |

---

## Part 7 · What to send me when it breaks

Three things, always the same three:

1. **A photo/screenshot** of the phone screen (or the exact words it shows).
2. The **first red block** in Android Studio's `Run` panel at the bottom (scroll up to the
   first red text, not the last).
3. If it says "Connected" but nothing moves: what you pressed, and whether the PC did
   anything.

With those I can tell you what to change without guessing.

---

## Part 8 · What comes next (so you know where this is going)

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
