# Houston apps for Android and iPhone

Houston already works on any phone from the browser (add it to your Home Screen for a full-screen app). The apps add a few things a web page can't do:

| | Android app | iPhone app |
|---|---|---|
| Houston, full screen | ✓ | ✓ |
| Home-screen widget (bitcoin price, status, hashrate, mode) | ✓ | ✓ |
| Quick-settings tile (status; Start, Stop, modes) | ✓ | – |
| Houston's alerts as phone notifications | ✓ (checked every 15 minutes) | – (use ntfy or Houston from the Home Screen) |
| Siri: “Hey Siri, Houston status”, “Switch Houston to Whisper” | – (use Houston's shortcut links) | ✓ |
| How you install it | Download the APK from GitHub | Build it with Xcode on a Mac |

Both apps show the Houston that runs on your Apollo, so they always match the Houston version installed there. They need Houston 2.5.0 or later on the Apollo.

## Away from home: still Tailscale

The apps talk to your Apollo directly, just like the browser, so the phone has to reach it: on your home Wi-Fi, or through [Tailscale](houston.md) when you're away. There's no Houston server in the cloud passing things along, by design: nothing about your Apollo leaves your own network.

That also means the Android app's notifications only arrive while the phone can reach the Apollo (Tailscale on when away). For instant alerts anywhere, without Tailscale, keep the **ntfy app** set up in Houston › Settings › Alerts as well.

## Android

### Install

1. On your phone, open the project's [Releases page](https://github.com/eisenreichGIT/houston-apollo/releases) and download **Houston-v….apk** from the newest release.
2. Open it. Android asks to allow installing apps from your browser (or Files app): allow it, then **Install**. Android may also offer to scan it with Play Protect; that's fine.
3. Open **Houston**, enter your Apollo's address (the IP from your router, like `192.168.1.50`, or its Tailscale name) and tap **Connect**.
4. Sign in with your Apollo dashboard password, as in the browser.
5. When the app asks **Widget, quick tile and notifications?**, tap **Turn on**, and allow notifications.

Updates: download and install the new APK the same way; your settings stay. [Obtainium](https://github.com/ImranR98/Obtainium) can watch the Releases page and update it for you.

### The widget

Long-press your home screen › **Widgets** › **Houston**, and drag it out. It shows the bitcoin price and its 24-hour change, a status dot, the hashrate, the power mode and the power use. It refreshes every 15 minutes; tap the round arrow to refresh now, or the widget to open Houston.

### The quick-settings tile

Pull down the quick settings twice, tap the pencil (edit), and drag **Apollo** into your tiles. It's lit while mining and shows the mode and hashrate. Tap it for Start, Stop and the power modes (Whisper, Eco, Balanced, Turbo; Apollo III: Super Eco instead of Whisper).

### Notifications

Every 15 minutes (the shortest Android allows for apps in the background), the app asks Houston for new alerts and shows them as notifications: stopped unexpectedly, running hot, hashrate drop, node stopped, drive almost full, solo block found, new Apollo software. Which alerts Houston sends is set in Houston › Settings › Alerts. Turn the app's notifications off, or send a test, in Houston › Settings › **App settings**.

### App settings

In Houston › Settings, the **Houston app** card at the top opens the app's own settings: change the Apollo's address, turn notifications on or off, send a test notification, or turn off the widget/tile pairing.

### What the app stores

The Apollo's address and Houston's **shortcut key** (the same key Siri shortcuts use), in the app's private storage on the phone. Your password isn't stored by the app; the Houston page keeps its usual sign-in, as in a browser. To revoke the app's access, make a new shortcut key in Houston › Settings › Siri, Google & shortcuts.

## iPhone

iPhones only install apps from the App Store, TestFlight, or a Mac running Xcode. Houston isn't on the App Store, so for now you build it on your Mac and install it on your iPhone with a cable.

### Build and install (about 20 minutes the first time)

You need a Mac with a recent macOS and **Xcode** (free, from the Mac App Store), your Apple ID, and the iPhone with its cable.

1. Install Homebrew if you don't have it (see [brew.sh](https://brew.sh)), then in Terminal:
   ```bash
   brew install xcodegen
   cd ~/Downloads/houston-apollo/ios     # wherever you unzipped or cloned the project
   xcodegen
   open Houston.xcodeproj
   ```
2. In Xcode, click **Houston** at the top of the left sidebar, then the **Signing & Capabilities** tab. For the **Houston** target and again for the **HoustonWidget** target: tick *Automatically manage signing* and pick your Apple ID under **Team** (Xcode › Settings › Accounts › + to add it).
   - If Xcode says the bundle identifier is taken, change `io.github.eisenreichgit.houston` to something of your own (e.g. `com.yourname.houston`), and the widget's to the same plus `.widget`.
3. Plug in the iPhone, unlock it, and tap **Trust**. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
4. In Xcode, pick your iPhone at the top, and press **Run** (▶). The first time, the iPhone asks you to trust your developer certificate: **Settings › General › VPN & Device Management** › your Apple ID › **Trust**.
5. Open **Houston**, enter the Apollo's address, sign in, and tap **Turn on** for Siri when asked. Allow local network access when asked.

With a free Apple ID, the app keeps working for **7 days**; then press Run again with the phone plugged in. A paid Apple Developer account (about $99 a year) makes builds last a year and lets you share the app with others through TestFlight.

### Widget and Siri

- **Widget**: long-press the home screen › **+** › **Houston**. Then long-press the widget › **Edit Widget**, and enter your Apollo's address. It refreshes about every 15 minutes.
- **Siri**: “Hey Siri, Houston status”, “Switch Houston to Whisper”, “Start mining with Houston”, “Stop mining with Houston”. The same actions are in the **Shortcuts** app under Houston.

### Alerts on iPhone

iPhone apps can't check in the background often enough for alerts. Use the ntfy app, or Houston added to the Home Screen from Safari with its https address (see [Alerts](houston.md#alerts-on-your-phone)).

## For developers

- `android/`: a small Java app (no third-party libraries): a WebView for Houston, a home-screen widget, a quick-settings tile and a JobScheduler job that checks Houston's `/api/v1/alerts`. GitHub Actions (`.github/workflows/android.yml`) builds it on every change and attaches the APK to releases.
- `ios/`: SwiftUI and WidgetKit, with App Intents for Siri. The Xcode project is generated from `ios/project.yml` with XcodeGen. GitHub Actions (`.github/workflows/ios.yml`) checks that it builds.
- Houston endpoints the apps use: `/api/device`, `/api/glance` and `/api/price` (public), `/api/v1/status`, `/api/v1/say`, `/api/v1/action/<action>` and `/api/v1/alerts?since=<epoch>` (shortcut key), and `/api/automation` (with the Houston sign-in, to get the shortcut key once).

### Signing the Android app

Android only installs an update if it's signed with the same key as the installed app, so releases need one fixed key, kept as GitHub secrets:

1. Create a key once (Java's `keytool`):
   ```bash
   keytool -genkeypair -v -keystore houston.jks -alias houston -keyalg RSA -keysize 4096 -validity 10000
   ```
2. In the repository on GitHub: **Settings › Secrets and variables › Actions › New repository secret**:
   - `HOUSTON_KEYSTORE_BASE64`: the key file as base64 (`base64 -w0 houston.jks` on Linux, `base64 -i houston.jks` on Mac, or PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("houston.jks"))`)
   - `HOUSTON_KEYSTORE_PASSWORD`: its password
3. Keep `houston.jks` and the password somewhere safe (a password manager). If they're lost, people have to uninstall the app once to install a build signed with a new key.

Without the secrets, GitHub builds a debug APK, fine for trying it but not for updates.

## Google's developer verification (2027)

Google is starting to require that Android apps come from verified developers, also outside the Play Store: from September 30, 2026 in Brazil, Indonesia, Singapore and Thailand, and worldwide in 2027. Until then, installing the APK from GitHub works as described. After that, sharing the app widely needs a verified developer account (or users installing through Android's advanced flow for unverified apps); Google's free hobbyist account allows sharing with up to 20 devices. See [Android developer verification](https://developer.android.com/developer-verification).
