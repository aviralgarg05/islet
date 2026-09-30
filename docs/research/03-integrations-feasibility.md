# 03 — Integrations Feasibility Report

**Scope:** open-source macOS notch / "Dynamic Island" app. Swift 6.4 + SwiftUI + AppKit, built with SwiftPM using Command Line Tools only (no Xcode.app). Unsandboxed, distributed outside the App Store, ad-hoc or Developer ID signed.
**Target machine:** MacBook Pro M3 Pro 14" with a notch, macOS 27.0.1 (build 26A434), Apple Swift 6.4 (swiftlang-6.4.0.34.1). CLT SDKs installed: MacOSX15.0, 26.5, 27.0.
**Date:** 2026-09-30

---

## 0. How to read this report

Each integration section covers **Approach**, **APIs and snippets**, **Permissions and entitlements**, **Public or private API risk**, **Reliability**, and a **Recommendation**, with sources at the end.

Reliability scale:

| Grade | Meaning |
|---|---|
| **A** | Public, documented API. Stable across OS releases. |
| **B** | Public API with quirks, or it needs a one-time user setup or a TCC grant. Works well in practice. |
| **C** | Private API, undocumented files, or a system-process hack. Works on macOS 27.0.1 today, but expect breakage on some OS updates. Needs a kill-switch and a fallback. |
| **D** | Not practically feasible, needs a restricted entitlement, or the cost to users (for example Full Disk Access) is out of proportion to the feature. |

Tags: **[VERIFIED]** means tested on this machine during this research. **[REPORTED]** means taken from a third-party source and not reproduced here.

### 0.1 Verified on this machine (macOS 27.0.1, CLT only)

These are empirical results from small probes compiled with `swiftc` and `clang` on this Mac:

1. **MediaRemote is blocked in-process.** An ad-hoc signed binary calling `MRMediaRemoteGetNowPlayingInfo` gets `nil`, `MRMediaRemoteGetNowPlayingApplicationPID` returns `0`, and `MRNowPlayingRequest.localNowPlayingItem` is `nil`. The same process *can* read the now-playing client's bundle ID via `localNowPlayingPlayerPath.client.bundleIdentifier`.
2. **MediaRemote works through `/usr/bin/perl`.** I wrote my own ad-hoc-signed dylib (not the third-party adapter) and loaded it into `/usr/bin/perl` via `DynaLoader::dl_load_file`. It got the full now-playing dictionary: 17 keys, title, and `com.spotify.client`. The identical dylib loaded into our own ad-hoc binary got `nil`. **An ad-hoc signed payload is enough, and Developer ID is not required.** This contradicts a claim in `ultra-media-remote`, at least for an unquarantined local build.
3. **MediaRemote works through JXA.** `/usr/bin/osascript -l JavaScript` loading `MediaRemote.framework` and calling `MRNowPlayingRequest.localNowPlayingItem` works. It returned Spotify, and later a Chrome video (`com.google.Chrome`, rate 1). Each call takes about 0.18–0.27 s wall-clock. Artwork bytes are **not** in the synchronous `nowPlayingInfo` (only `ArtworkIdentifier`, `ArtworkMIMEType`, width and height).
4. `/usr/bin/perl` is still present (perl 5.34.1), as is `/usr/bin/osascript`.
5. **Notch geometry on the built-in display:**
   - `frame` = 1512×982 pt, `safeAreaInsets.top` = 32.
   - `auxiliaryTopLeftArea` = (0, 950, 663.5, 32) and `auxiliaryTopRightArea` = (848.5, 950, 663.5, 32), so the **notch is 185 × 32 pt**.
   - Menu bar height (`frame.maxY - visibleFrame.maxY`) = 33.
   - The external display returns `safeAreaInsets.top = 0` and `aux* = nil`. Its `localizedName` is **empty**.
   - The built-in display's `localizedName` = "Built-in Retina Display".
6. **Window levels:** normal 0, floating 3, modalPanel 8, **mainMenu 24**, **statusBar 25**, popUpMenu 101, overlay 102, screenSaver 1000, assistiveTechHigh 1500, **CGShieldingWindowLevel 2147483628**, cursor 2147483630.
7. **Private symbols resolve via `dlsym`:**
   - DisplayServices: `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness`, `DisplayServicesRegisterForBrightnessChangeNotifications`.
   - CoreDisplay: `CoreDisplay_Display_GetUserBrightness` and `CoreDisplay_Display_SetUserBrightness`.
   - MediaRemote: `MRMediaRemoteSendCommand`, `MRMediaRemoteSetElapsedTime`, `MRMediaRemoteRegisterForNowPlayingNotifications`.
   - SkyLight: `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSAddWindowsToSpaces`, `CGSCopyManagedDisplaySpaces`.
   - Reads succeed: `DisplayServicesGetBrightness(main)` returned rc=0 and 0.577. CoreBrightness `KeyboardBrightnessClient brightnessForKeyboard:1` returned 0.001.
8. **CoreAudio and CoreMediaIO work without prompts.**
   - `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` ('vmvc') via `AudioObjectGetPropertyData` reads 0.68, is settable, and `AudioObjectAddPropertyListenerBlock` on it returns 0.
   - `kAudioHardwarePropertyProcessObjectList` returned 31 process objects, and `kAudioProcessPropertyIsRunningInput` and `IsRunningOutput` are readable.
   - `kCMIODevicePropertyDeviceIsRunningSomewhere` is readable on 3 cameras.
   - None of this triggered a TCC prompt.
9. **TCC-protected without Full Disk Access (FDA):** listing `~/Library/DoNotDisturb/DB/` gives "Operation not permitted". So do listing and reading `~/Library/Group Containers/group.com.apple.usernoted/db2/`. As a control, `~/Library/Preferences` is readable and `~/Library/Mail` is blocked.
10. `NSPasteboard.accessBehavior` (macOS 15.4+) exists in the 27.0 SDK. The header documents that the General pasteboard default is to **ask** on programmatic access. `changeCount` can be read freely.
11. **Testing:** `import XCTest` fails under CLT ("unable to resolve module dependency: 'XCTest'"). `import Testing` compiles, but by default `@Test` fails with "plugin for module 'TestingMacros' not found". **Workaround verified:** `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` passes. `--build-system native` is deprecated and fails worse ("no such module 'Testing'").
12. **Tools present in CLT:** `codesign`, `notarytool`, `stapler`, `plutil`, `PlistBuddy`, `iconutil`, `lipo`, `swift-stdlib-tool`, `notifyutil`, `shortcuts`.
    **Missing (Xcode-only):** `actool`, `ibtool`, `xcstringstool`, `momc`, `appintentsmetadataprocessor`. `sdef` exists as `/usr/bin/sdef` but errors with "requires Xcode". `sdp` is only a `/usr/bin` shim with no Xcode-backed tool behind it.
13. `codesign --sign - -r='designated => identifier "…"'` produces an ad-hoc bundle whose DR is identifier-only rather than `cdhash H"…"`, and `codesign --verify --strict` accepts it.
14. **SwiftPM (new build system):**
    - `.build/release` is a symlink to `.build/out/Products/Release`.
    - The generated `Bundle.module` accessor searches `Bundle.main.resourceURL` first, so resource bundles belong in `Contents/Resources/`.
    - The default rpaths are `/usr/lib/swift` and a CLT `swift-6.2/macosx` path. No `@executable_path/../Frameworks` is added.
15. **Distributed notifications (inconclusive).** A passive 4-minute listener for `com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo` received nothing, but playback state may not have changed during that window. Treat these notifications as best-effort.

---

## 1. Summary matrix

| # | Integration | Recommended approach | API class | User permission | Grade |
|---|---|---|---|---|---|
| 1 | Now Playing (all apps and browsers) | MediaRemote via `/usr/bin/perl` adapter (stream). Commands in-process via `MRMediaRemoteSendCommand`. JXA as fallback. AppleScript per app for extras. | Private plus platform-binary trick | None (Automation only for app-specific AppleScript) | **C** (works now; single point of failure) |
| 2 | Notch geometry and window | `NSScreen.safeAreaInsets` / `auxiliaryTop*Area`, `NSPanel` non-activating at `.mainMenu+3`, `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]` | Public (lock screen and fullscreen detection are private) | None | **A** (lock-screen **C**) |
| 3 | Volume / brightness / backlight HUD | CoreAudio (public). DisplayServices and CoreBrightness (private). CGEventTap swallowing `NX_SYSDEFINED` keys to suppress the system HUD. | Mixed | Accessibility (for HUD suppression) | Volume **A**, brightness **C**, suppression **C** |
| 4 | Battery | IOKit `IOPS*` and `ProcessInfo.isLowPowerModeEnabled` | Public | None | **A** |
| 5 | Calendar and Reminders | EventKit `requestFullAccessToEvents/Reminders`, `EKEventStoreChanged` | Public | Calendars, Reminders | **A** |
| 6 | Mirroring other apps' notifications | Opt-in AX observer on Notification Center UI. Optional FDA DB reader. Push API is primary. | Undocumented UI or DB | Accessibility or FDA | **C** / **D** |
| 7 | File shelf / AirDrop | `NSDraggingDestination`, drag-pasteboard detection, `NSSharingService(.sendViaAirDrop)`, `QLThumbnailGenerator`, bookmarks | Public | None | **A** |
| 8 | Bluetooth / AirPods battery | IOBluetooth connect notifications plus private KVC battery keys. IORegistry `BatteryPercent` for Magic devices. | Mixed | Bluetooth | **C** (AirPods) / **B** (Magic devices) |
| 9 | Downloads progress | `Progress.addSubscriber(forFileURL:)` on `~/Downloads` (not deprecated) | Public | Possibly Downloads-folder TCC | **B** |
| 9b | Mic / camera in use | CoreAudio process objects (macOS 14.2+), CMIO `DeviceIsRunningSomewhere` | Public | None | **A** |
| 9c | Screen recording in progress | No API; heuristics only | none | — | **D** |
| 10 | Focus / DND | Shortcuts automations to URL scheme. Optional FDA reader of `Assertions.json`. | Public (Shortcuts) or undocumented | Shortcuts setup, or FDA | **B** (Shortcuts) / **C** |
| 10b | Shortcuts | `/usr/bin/shortcuts run`, URL scheme. **App Intents not possible without Xcode.** | Public | None | **A** (run) / **D** (App Intents) |
| 11 | Webcam mirror | `AVCaptureSession` plus `AVCaptureVideoPreviewLayer` in `NSViewRepresentable` | Public | Camera | **A** (TCC churn with ad-hoc) |
| 12 | Weather | Open-Meteo (no key) plus CoreLocation or a manual city | Public web | Location (optional) | **A** |
| 13 | Clipboard history | `changeCount` polling. Read content only on opt-in. Respect pasteboard privacy. | Public | "Paste" privacy prompt (if enforced) | **B** |
| 14 | System stats | Mach `host_processor_info` / `host_statistics64`, `sysctl NET_RT_IFLIST2`, IOKit. Temperatures via private IOHID. | Public (temps private) | None | **A** (temps **C**) |
| 15 | Extensibility | Unix-socket HTTP API plus optional loopback TCP with token, URL scheme, bundled CLI, AppleScript `sdef`, Darwin notify | Public | None | **A** |
| 16 | Packaging / updates / tests | Script-assembled `.app`, `codesign`, `notarytool` (Developer ID), `SMAppService.mainApp`, Sparkle via SPM, Swift Testing with plugin-path flag | Public | — | **A/B** |
| 17 | Liquid Glass | `glassEffect`, `GlassEffectContainer`, `NSGlassEffectView` (macOS 26+). Use sparingly; keep the closed notch pure black. | Public | — | **A** |

---

## 2. Now Playing (§1 of brief)

### 2.1 State of MediaRemote in macOS 15.4 → 26 → 27

- Since **macOS 15.4**, `mediaremoted` checks the client. Ordinary third-party processes get empty replies from `MRMediaRemoteGetNowPlayingInfo`, the PID and "is playing" calls, and `MRNowPlayingRequest`. **[VERIFIED on 27.0.1, §0.1 item 1.]**
- The gate is on **Apple platform binaries**, not on a grantable entitlement. `ungive/mediaremote-adapter` credits the finding that "processes with a bundle identifier starting with `com.apple.` are granted permission". `roger` #27 puts it as "the entitlement gate sits on the process, not on the API surface".
- **Sending commands still works in-process.** `MRMediaRemoteSendCommand`, `MRMediaRemoteSetElapsedTime`, `MRMediaRemoteSetShuffleMode` and `MRMediaRemoteSetRepeatMode` are used directly by boring.notch's `NowPlayingController` (current `main`). LyricFever #94 reports the same. **[REPORTED; symbols verified present on 27.0.1, commands not exercised so as not to disturb the user's playback.]**
- **macOS 27:** the adapter README's badge lists macOS 27.0 (26A5425a). There are no open adapter issues about 26 or 27 breakage (only #41, #28, #24, #23). boring.notch's current `main` still ships the adapter.

### 2.2 Option A (primary): `ungive/mediaremote-adapter`, via perl

- **How it works:** `/usr/bin/perl mediaremote-adapter.pl /path/MediaRemoteAdapter.framework <COMMAND>`. Perl is an Apple platform binary, and the script `DynaLoader`-loads the helper framework, which calls MediaRemote and prints JSON.
- **License:** BSD-3-Clause (Jonas van den Berg). Embedding is fine. Include the license text in an "Acknowledgements" screen or file and in the repo `LICENSES/`.
- **Files to bundle (not linked):** `mediaremote-adapter.pl` in `Contents/Resources/`, `MediaRemoteAdapter.framework` in `Contents/Frameworks/`, and optionally `MediaRemoteAdapterTestClient` for the `test` command. Build with CMake (`cmake .. && cmake --build .`, which produces arm64 and x86_64). CMake is available at `/opt/homebrew/bin/cmake`. **Pin a commit and build in CI.** Do not commit prebuilt binaries you did not build.
- **Commands:**
  - `stream [--no-diff] [--debounce=N] [--micros] [--no-artwork]` emits JSON lines `{"type":"data","diff":bool,"payload":{…}}`. With diff on, merge the payload into the last full payload; keys that disappear are sent as `null`.
  - `get` prints one snapshot.
  - `send <0-13>`: 0 play, 1 pause, 2 toggle, 3 stop, 4 next, 5 previous, 6 shuffle toggle, 7 repeat toggle, 8/9 start and end forward seek, 10/11 start and end backward seek, 12 back 15 s, 13 skip 15 s.
  - `seek <microseconds>`.
  - `test` exits 0 when the adapter is functional. Use it at startup as a health check.
- **Payload keys:**
  - Mandatory: `bundleIdentifier`, `playing`, `title`.
  - Plus: `parentApplicationBundleIdentifier` (useful for browser helper processes), `artist`, `album`, `duration`, `elapsedTime`, `timestamp`, `playbackRate`, `artworkData` (base64), `artworkMimeType`, `isLiked`, `shuffleMode`, `repeatMode`, `mediaType`, `uniqueIdentifier`, and more.
  - The README notes: "Metadata such as `artworkData` and `artworkMimeType` often takes a bit of time to load and may not appear in the output in all cases."
- **Swift integration sketch:**

```swift
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
p.arguments = [
  Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")!.path,
  Bundle.main.privateFrameworksURL!.appendingPathComponent("MediaRemoteAdapter.framework").path,
  "stream", "--debounce=100"
]
let out = Pipe(); p.standardOutput = out
var buffer = Data()
out.fileHandleForReading.readabilityHandler = { h in
  buffer.append(h.availableData)            // chunked: split on "\n", decode each full line
  while let nl = buffer.firstIndex(of: 0x0A) {
    let line = buffer[..<nl]; buffer.removeSubrange(...nl)
    // JSONDecoder → merge diff into last state → publish on MainActor
  }
}
p.terminationHandler = { _ in /* back-off restart; after N failures switch to JXA fallback */ }
try p.run()
```

- **Progress interpolation:** `position = elapsedTime + (now - timestamp) * playbackRate`. Drive a SwiftUI `TimelineView(.periodic(from:by: 0.5))` instead of polling the adapter.
- **Maintained Swift wrapper:** `ejbills/mediaremote-adapter` (SPM product `MediaRemoteAdapter`, class `MediaController` with `startListening()` and `onTrackInfoReceived`). No license is declared on GitHub, so **do not depend on it until a license is added**. Vendoring the BSD-licensed upstream is cleaner.
- **Maintenance risk:** Apple warned in the Catalina release notes that scripting runtimes (Perl, Python, Ruby) would not be included by default in future macOS versions. Perl still ships on 27.0.1. If Apple removes perl or tightens the platform-binary rule, this path dies. Keep Option B ready.

### 2.3 Option B (fallback, zero third-party code): JXA via `osascript`

**[VERIFIED on 27.0.1]** This works and costs about 0.2 s per call:

```js
// np.js — run with: /usr/bin/osascript -l JavaScript np.js
ObjC.import('Foundation');
$.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
const req = $.NSClassFromString('MRNowPlayingRequest');
const item = req.localNowPlayingItem;
const info = item.isNil() ? null : item.nowPlayingInfo;
JSON.stringify({
  client: ObjC.unwrap(req.localNowPlayingPlayerPath.client.bundleIdentifier),
  title:  info && ObjC.unwrap(info.valueForKey('kMRMediaRemoteNowPlayingInfoTitle')),
  rate:   info && ObjC.unwrap(info.valueForKey('kMRMediaRemoteNowPlayingInfoPlaybackRate')),
  elapsed:info && ObjC.unwrap(info.valueForKey('kMRMediaRemoteNowPlayingInfoElapsedTime')),
  duration:info && ObjC.unwrap(info.valueForKey('kMRMediaRemoteNowPlayingInfoDuration'))
});   // last expression is printed to stdout; console.log goes to stderr
```

- Poll it on a timer, for example every 1 s while playing and every 5 s while idle. Alternatively, keep one long-running `osascript` process that loops, writes lines with `$.NSFileHandle.fileHandleWithStandardOutput`, and sleeps with `delay()`.
- **Artwork:** not available synchronously (only `ArtworkIdentifier` and MIME type are present). Fall back to app-specific artwork (§2.4) or a generic icon.
- osascript is a core OS component and less likely to disappear than perl. The platform-binary gate applies to it the same way, so if Apple closes the loophole, both A and B die together.

### 2.4 Option C: app-specific AppleScript (Music.app, Spotify)

- **Spotify dictionary** (read from `/Applications/Spotify.app/Contents/Resources/Spotify.sdef` on this Mac):
  - Properties: `current track`, `player state`, `player position` (real seconds, **settable**, so seeking works), `sound volume` (0–100), `shuffling`, `repeating`.
  - Track properties: `name`, `artist`, `album`, `duration` (**ms** in practice; the sdef says "seconds", so verify), `id`, `artwork url` (use this; `artwork` is "deprecated and will never be set"), `spotify url`, `starred`, `popularity`.
  - Commands: `playpause`, `play`, `pause`, `next track`, `previous track`, `play track`.
- **Music.app:** `player state`, `player position` (settable), `sound volume`, `current track` (name, artist, album, duration, `favorited`), and artwork via `data of artwork 1 of current track`. The artwork comes back as raw image data; read `NSAppleEventDescriptor.data`.
- **Execution options:**
  - `NSAppleScript`: not thread-safe, so keep it on one serial executor.
  - `OSAKit`'s `OSAScript`.
  - Raw Apple Events via `NSAppleEventDescriptor`: the fastest option, with no compile step.
  - **ScriptingBridge header generation (`sdef | sdp`) needs Xcode [VERIFIED].** Either hand-write the `@objc protocol`s or avoid ScriptingBridge.
- **Permissions:**
  - Automation TCC per target app, prompted on first send. `NSAppleEventsUsageDescription` must be in Info.plist.
  - Under hardened runtime, the `com.apple.security.automation.apple-events` entitlement is **required**, or events fail silently with -1743.
  - Pre-check with `AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, askUserIfNeeded: false)`.
  - Guard every call with `NSRunningApplication.runningApplications(withBundleIdentifier:)`. Sending an event to a closed app **launches** it.
- **Change notifications (no permission needed):**
  - `DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), …)`. userInfo keys as documented by the community: "Player State", "Name", "Artist", "Album", "Track ID", "Duration", "Playback Position", "Has Artwork".
  - `com.apple.Music.playerInfo` is the successor of `com.apple.iTunes.playerInfo`. Keys include "Player State", "Name", "Artist", "Album", "Total Time", "PersistentID".
  - Use them only as cheap "something changed" triggers. They were not observed in the passive test (§0.1 item 15).

### 2.5 Browser media (Chrome, Arc, Safari, Firefox)

1. **MediaRemote already covers browsers.** Chromium browsers and Safari publish Media Session metadata to the system Now Playing center.
   - **[VERIFIED]** A Chrome video showed up via JXA with `client = com.google.Chrome`, `PlaybackRate = 1`, and `Duration`, `ElapsedTime`, `ArtworkIdentifier`.
   - The adapter adds `parentApplicationBundleIdentifier` for helper-process attribution.
   - Controls (play, pause, seek) work because the browser registers MPRemoteCommand handlers.
   - **This should be the only browser path in v1.**
2. **AppleScript `execute javascript`.** Chrome's `scripting.sdef` has `execute … javascript` **[VERIFIED in the local sdef]**. Safari has `do JavaScript`.
   - The user must enable "Allow JavaScript from Apple Events": View → Developer in Chrome; Settings → Developer in Safari.
   - Errors: -1743 means Automation is denied; -1723 means the browser setting is off.
   - Chromium treats this toggle as a security-sensitive setting. Do **not** automate turning it on.
   - Use it only for power-user features such as per-tab lists or YouTube-specific actions.
3. **Browser extension plus native messaging** (for per-tab and multi-session state):
   - The extension uses the `nativeMessaging` permission.
   - Place a host manifest (`{"name","description","path","type":"stdio","allowed_origins":["chrome-extension://<id>/"]}`) in the browser's `NativeMessagingHosts/` folder:
     - Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
     - Firefox: `~/Library/Application Support/Mozilla/NativeMessagingHosts/`
     - Edge, Brave, Arc and others have their own profile roots (verify per browser).
   - The host is a tiny CLI in `Contents/Helpers/` that relays to the app's Unix socket (§16).
   - Alternatively, an MV3 service worker can open a `ws://127.0.0.1:<port>` WebSocket to the app. That is simpler, but needs the token model from §16.
   - Safari Web Extensions must be packaged inside an app extension built with Xcode, so they are **not feasible with CLT**.

### 2.6 Artwork, seek, media keys

- **Artwork priority:**
  1. Adapter `artworkData` (base64) with `artworkMimeType`.
  2. Spotify `artwork url`, fetched over HTTPS.
  3. Music `data of artwork 1`.
  4. The app icon of `bundleIdentifier`, via `NSWorkspace.shared.icon(forFile:)` on the app URL.
  - Cache by `uniqueIdentifier` or `contentItemIdentifier`.
  - Extract a dominant color (CIAreaAverage) for the visualizer tint.
- **Seek / scrub:**
  - Adapter `seek <µs>`, or in-process `MRMediaRemoteSetElapsedTime(seconds)`.
  - Spotify and Music: `set player position to <s>`.
  - Throttle scrubbing and send on drag-end. Some players ignore rapid seeks.
- **Media keys (last-resort control that works with any player):**

```swift
import AppKit
import IOKit.hidsystem   // NX_KEYTYPE_PLAY = 16, NEXT = 17, PREVIOUS = 18, FAST = 19, REWIND = 20 (ev_keymap.h)

func postAuxKey(_ key: Int32) {
  for down in [true, false] {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
    let data1 = Int((key << 16) | (down ? 0xA00 : 0xB00))
    NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                       data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
  }
}
```

Posting synthetic events needs the app to be trusted for **Accessibility** (post-event access). Check with `CGPreflightPostEventAccess()` and request with `CGRequestPostEventAccess()`.

- In-process command sketch (private; signature reverse-engineered):

```swift
let mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
typealias MRSend = @convention(c) (UInt32, CFDictionary?) -> Bool
typealias MRSetElapsed = @convention(c) (Double) -> Void
let send = unsafeBitCast(dlsym(mr, "MRMediaRemoteSendCommand"), to: MRSend.self)
let setElapsed = unsafeBitCast(dlsym(mr, "MRMediaRemoteSetElapsedTime"), to: MRSetElapsed.self)
_ = send(2, nil)        // kMRTogglePlayPause
setElapsed(93.5)
```

### 2.7 Recommendation

Build a `NowPlayingProvider` protocol with three implementations, chosen by a runtime health check:

1. `AdapterProvider`: perl `stream`. Run `test` first.
2. `JXAProvider`: polling.
3. `AppleScriptProvider`: Music and Spotify only, opt-in, needs Automation.

Send commands through in-process MediaRemote first. Fall back to adapter `send` or `seek`, then media keys.

Ship a **kill-switch** for each provider (a remote-config flag or a Settings toggle) and a visible "Now Playing unavailable on this macOS build" state.

**Sources:**
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
[README](https://github.com/ungive/mediaremote-adapter/blob/master/README.md),
[adapter issues](https://github.com/ungive/mediaremote-adapter/issues),
[ejbills fork](https://github.com/ejbills/mediaremote-adapter),
[roger #27 JXA probe](https://github.com/MaxBroda/roger/issues/27),
[ultra-media-remote](https://github.com/michael-berardi/ultra-media-remote),
[LyricFever #94](https://github.com/aviwad/LyricFever/issues/94),
[boring.notch NowPlayingController (GPL-3.0)](https://github.com/TheBoredTeam/boring.notch),
[Chromium AppleScript info](https://www.chromium.org/developers/applescript/),
[Chrome "Allow JavaScript from Apple Events" notes](https://gist.github.com/terrylica/d42b26ea559c0c6d8c46b95579102188/dcfbb7b189a7bd0ad87a7a67965e212724713b9f),
[Chromium security issue 40092604](https://issues.chromium.org/issues/40092604),
[Emulating special keys](https://www.smallpearl.com/blog/how-to-programmatically-emulate-appple-special-key),
[The Apple Wiki: MediaRemote](https://theapplewiki.com/wiki/Dev:MediaRemote.framework).

---

## 3. Notch geometry and the notch window (§2 of brief)

### 3.1 Geometry (public, macOS 12+) — Grade A

```swift
extension NSScreen {
  var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
  var isBuiltIn: Bool { displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
  /// Stable across reboots and locale changes (unlike localizedName).
  var stableUUID: String? {
    guard let id = displayID, let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, u) as String
  }
  var hasNotch: Bool { safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil }
  /// Notch rect in global screen coordinates (uses widths only, to be origin-agnostic).
  var notchRect: CGRect? {
    guard hasNotch, let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
    let w = frame.width - l.width - r.width
    return CGRect(x: frame.minX + l.width, y: frame.maxY - safeAreaInsets.top, width: w, height: safeAreaInsets.top)
  }
  var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }   // 0 when auto-hidden / no menu bar
}
```

- **Measured on this M3 Pro:** notch 185×32 pt, menu bar 33 pt (§0.1 item 5).
- **Non-notch displays:** draw a "virtual notch" pill centered at the top. Use a configurable height, `menuBarHeight`, or `NSStatusBar.system.thickness`.
- **Persist the chosen display by `stableUUID`, never by `localizedName`.** Atoll broke on macOS 27 because the built-in display's localized name changed; the notch was invisible on the desktop and only visible on the lock screen (Atoll #632). This machine's external display even returns an empty `localizedName`.

### 3.2 Window configuration — Grade A

```swift
final class NotchPanel: NSPanel {
  var allowsKey = false                          // flip to true only while a text field is focused
  init(frame: CGRect) {
    super.init(contentRect: frame,
               styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .mainMenu + 3                        // 27: above menu bar (24) & status items (25), below pop-up menus (101)
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    isOpaque = false; backgroundColor = .clear; hasShadow = false
    isMovable = false; hidesOnDeactivate = false; isReleasedWhenClosed = false
    becomesKeyOnlyIfNeeded = true
    // sharingType = .none                       // optional: hide from screenshots/screen sharing
  }
  override var canBecomeKey: Bool { allowsKey }
  override var canBecomeMain: Bool { false }
}
```

- **Level:**
  - boring.notch uses `.mainMenu + 3` = 27. NotchDrop uses `.statusBar + 8` = 33.
  - Both sit above the menu bar but below pop-up menus (101), so status-item menus still draw on top.
  - **Avoid `CGShieldingWindowLevel()` (2147483628) and `.screenSaver` (1000).** They cover system alerts, Spotlight and the like, and are meant for display capture.
- **Over fullscreen apps:** `.fullScreenAuxiliary` plus `.canJoinAllSpaces` makes the panel appear on fullscreen Spaces.
  - To **hide during fullscreen video**, detect fullscreen Spaces yourself:
  - **Public heuristic:** on `NSWorkspace.activeSpaceDidChangeNotification` and `didActivateApplicationNotification`, call `CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)`. Look for a layer-0 window of the frontmost app whose bounds equal the screen frame. Bounds, layer and owner PID are available **without** Screen Recording permission; only `kCGWindowName` needs it.
  - **Private and more accurate:** `CGSCopyManagedDisplaySpaces(CGSMainConnectionID())` and read Space types. `TheBoredTeam/MacroVisionKit` is MIT-licensed and wraps this as `FullScreenMonitor.shared.spaceChanges()`.
- **Lock screen (private, C):** ordinary windows never show on the lock screen.
  - boring.notch uses a SkyLight Space created with `CGSSpaceCreate` / `SLSSpaceCreate`, then `…SetAbsoluteLevel(…, Int32.max)` and `…AddWindowsToSpaces` (its `CGSSpace.swift` is MPL-2.0).
  - It also uses `Lakr233/SkyLightWindow` (MIT, SwiftPM; `.moveToSky()` modifier).
  - Make this an opt-in "Show on Lock Screen" feature.
- **Screen changes:**
  - Observe `NSApplication.didChangeScreenParametersNotification` and rebuild the panels, as NotchDrop does.
  - Also observe `NSWorkspace.activeSpaceDidChangeNotification`, `NSWorkspace.didWakeNotification` / `screensDidWakeNotification`, and the distributed `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`.
  - `CGDisplayRegisterReconfigurationCallback` gives finer-grained events.
  - Debounce by about 300 ms; displays settle in several steps.
- **Mouse tracking without stealing focus:**
  - Use an `.nonactivatingPanel` and `canBecomeKey = false`. Clicking the panel does not activate the app or steal key focus from the user's app.
  - Hover: add an `NSTrackingArea` with `[.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]`. `.activeAlways` is required because the app is never active. SwiftUI `.onHover` inside a non-key panel is less reliable; prefer an AppKit tracking area or monitors.
  - Global monitors: `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown])` plus a matching `addLocalMonitorForEvents` (global monitors don't see your own app's events). **Mouse events need no permission; key events need Accessibility.** NotchDrop uses exactly this.
  - To expand the shelf when the user starts dragging a file anywhere, snapshot `NSPasteboard(name: .drag).changeCount` on global `leftMouseDown`, then compare on `leftMouseDragged` (boring.notch `DragDetector`).
- **Click-through:**
  - Keep the collapsed panel's frame tight to the notch shape plus a small hover margin, and resize it on expand. Alternatively, keep a larger panel and toggle `ignoresMouseEvents` from the global mouse-position monitor (true when outside the interactive shape).
  - Don't rely on transparent pixels passing clicks through.
- **Haptics:** `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` on expand. Atoll reports that haptics are intermittent on macOS 27.
- **macOS 27 context:**
  - Apple added a "»" overflow for menu-bar items hidden by the notch.
  - Six Colors reports the menu-bar changes "seem to have broken compatibility with existing menu bar utilities".
  - Apple still exposes no notch or Live-Activity API for Macs.

**Sources:**
[NSScreen.auxiliaryTopLeftArea](https://developer.apple.com/documentation/AppKit/NSScreen/auxiliaryTopLeftArea-uglc),
[safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets),
[NotchDrop (MIT)](https://github.com/Lakr233/NotchDrop),
[boring.notch window/space code (GPL-3.0)](https://github.com/TheBoredTeam/boring.notch),
[SkyLightWindow (MIT)](https://github.com/Lakr233/SkyLightWindow),
[MacroVisionKit (MIT)](https://github.com/TheBoredTeam/MacroVisionKit),
[DynamicNotchKit (MIT)](https://github.com/MrKai77/DynamicNotchKit),
[Atoll #632 macOS 27 issues](https://github.com/Ebullioscopic/Atoll/issues/632),
[Six Colors: macOS Golden Gate first look](https://sixcolors.com/post/2026/07/first-look-macos-golden-gate-public-beta/),
[Notchy guide (macOS 27 notch statement)](https://notchy.dev/blog/dynamic-island-for-macbook-guide/).

---

## 4. Volume / brightness / keyboard-backlight HUD replacement (§3 of brief)

### 4.1 Volume (public CoreAudio) — Grade A **[VERIFIED read, settable, and listener]**

```swift
import CoreAudio; import AudioToolbox
func defaultOutput() -> AudioObjectID {
  var id = AudioObjectID(kAudioObjectUnknown); var sz = UInt32(MemoryLayout<AudioObjectID>.size)
  var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &id); return id
}
var vmvc = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                      mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
func volume(_ d: AudioObjectID) -> Float32 { var v: Float32 = 0; var s = UInt32(4); AudioObjectGetPropertyData(d, &vmvc, 0, nil, &s, &v); return v }
func setVolume(_ d: AudioObjectID, _ v: Float32) { var v = v; AudioObjectSetPropertyData(d, &vmvc, 0, nil, 4, &v) }
AudioObjectAddPropertyListenerBlock(defaultOutput(), &vmvc, .main) { _, _ in /* show HUD */ }
```

- Mute uses `kAudioDevicePropertyMute` (output scope).
- Listen to `kAudioHardwarePropertyDefaultOutputDevice` on the system object and re-attach device listeners when it changes (AirPods connect, HDMI).
- Some outputs (HDMI or DisplayPort audio, some USB DACs) have no volume control: `AudioObjectHasProperty` is false. Show "fixed volume".
- `VirtualMasterVolume` is the deprecated alias; use `VirtualMainVolume` ('vmvc').
- boring.notch instead averages `kAudioDevicePropertyVolumeScalar` over elements 0–4. That also works, but 'vmvc' matches what the system slider uses.
- Feedback "pop": honour the `com.apple.sound.beep.feedback` global default. Play `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff`; this file exists on 27.0.1 **[VERIFIED]**.

### 4.2 Display brightness (private) — Grade C **[VERIFIED read]**

- `DisplayServicesGetBrightness(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32` and `DisplayServicesSetBrightness(CGDirectDisplayID, Float) -> Int32`, loaded with `dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")`.
- Alternatives:
  - `CoreDisplay_Display_GetUserBrightness` / `SetUserBrightness` (private).
  - For old Intel and external displays: `IODisplayGetFloatParameter(…, kIODisplayBrightnessKey)`, which boring.notch keeps as a fallback.
- **External monitors:** need DDC/CI over `IOAVService` on Apple Silicon, all private (see MonitorControl, MIT). BetterHUD explicitly skips them.
- **Change notifications:** `DisplayServicesRegisterForBrightnessChangeNotifications` is exported **[VERIFIED symbol]**, but its callback signature is undocumented (brightboi #6). Options:
  - Reverse-engineer and verify the signature.
  - Poll at 5–10 Hz only while the HUD is showing or a brightness key was just seen.
  - Handle all brightness keys yourself (§4.4), so you already know every change that comes from keys.
- **macOS 27.2 beta risk:** boring.notch #1575 (2026-09-22) reports that the 27.2 beta "redesigned the UI … for adjusting brightness" and broke its brightness OSD. It then worked again after a restart. Expect churn here.

### 4.3 Keyboard backlight (private) — Grade C **[VERIFIED read]**

- `CoreBrightness.framework` class `KeyboardBrightnessClient`, selectors `brightnessForKeyboard:` and `setBrightness:forKeyboard:`, keyboard ID 1.
- Call through `class_getInstanceMethod` / `method_getImplementation` cast to `@convention(c)`, as boring.notch's XPC helper does.
- There are **no change notifications**. Perch left backlight out because "nothing on macOS publishes a change to it".
- Keys `NX_KEYTYPE_ILLUMINATION_UP` / `DOWN` / `TOGGLE` (21, 22, 23) arrive through the same event tap.

### 4.4 Suppressing the system OSD — Grade C

macOS 26 moved the volume and brightness HUD to a small Control-Center-style popover at the top right. `OSDUIHelper.app` still exists in `/System/Library/CoreServices/` on 27.0.1 and is launched on demand **[VERIFIED present]**.

| Technique | Used by | Pros | Cons |
|---|---|---|---|
| **CGEventTap at `.cghidEventTap`, `.headInsertEventTap`, `.defaultTap`, mask `1 << 14` (NX_SYSDEFINED); swallow subtype-8 events for keys 0, 1, 2, 3, 7 (and 21, 22, 23); re-implement the action** | boring.notch `MediaKeyInterceptor`, BetterHUD, volumeHUD, CreativeNotch (then removed to drop the permission) | Clean: the system never sees the key, so no HUD appears | Needs **Accessibility** (BetterHUD: Input Monitoring is *not* required). You must re-implement step logic: 1/16 steps, Shift+Option = 1/64, Option+key opens Settings. External-display brightness is lost unless you implement DDC. The tap can be disabled by timeout, so re-enable on `.tapDisabledByTimeout` / `.tapDisabledByUserInput`. |
| `SIGSTOP` OSDUIHelper (resume with `SIGCONT` on quit) | Perch PR #30 | No key re-implementation | Hacky. `didLaunchApplicationNotification` does not fire for OSDUIHelper. One native HUD slips through per session. Fragile if Apple moves HUD rendering (27.2 beta signs). |
| `killall OSDUIHelper` | old hacks | — | launchd respawns it. **Don't.** |

Event-tap core:

```swift
import IOKit.hidsystem
let mask = CGEventMask(1 << 14)                              // NX_SYSDEFINED
let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: mask, callback: { _, type, event, refcon in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      /* CGEvent.tapEnable(tap:enable:true) via refcon */ return Unmanaged.passUnretained(event)
    }
    guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
    let key = Int32((ns.data1 & 0xFFFF_0000) >> 16)
    let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
    switch key {
    case NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE,
         NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN,
         NX_KEYTYPE_ILLUMINATION_UP, NX_KEYTYPE_ILLUMINATION_DOWN:
      if isDown { /* hop to MainActor: adjust value + show notch HUD */ }
      return nil                                              // swallow down AND up
    default: return Unmanaged.passUnretained(event)
    }
  }, userInfo: nil)
```

Keep the callback allocation-free and fast. Heavy work in the callback triggers the timeout-disable.

### 4.5 Recommendation

- **v1:** show the notch HUD from CoreAudio listeners (volume) and brightness polling while the HUD is visible, *alongside* the system HUD. This needs no permission.
- **"Replace system HUD" toggle:** turning it on requests Accessibility and installs the event tap, which suppresses the system HUD for keyboard-originated changes.
- Put brightness and backlight behind a capability check (`dlsym` present and the call returns 0), with a remote kill-switch.
- Do **not** use SIGSTOP.

**Sources:**
[BetterHUD (GPL-3.0)](https://github.com/connorpodea/BetterHUD),
[volumeHUD](https://github.com/dannystewart/volumeHUD),
[Perch PR #30](https://github.com/Milanpatel35/Perch/pull/30),
[CreativeNotch PR #17](https://github.com/GcdZ03/CreativeNotch/pull/17),
[boring.notch MediaKeyInterceptor / XPC helper](https://github.com/TheBoredTeam/boring.notch),
[boring.notch #1575 (27.2 beta OSD)](https://github.com/TheBoredTeam/boring.notch/issues/1575),
[brightboi #6 (brightness notifications)](https://github.com/joaodavidsilva/brightboi/issues/6),
[MonitorControl (MIT)](https://github.com/MonitorControl/MonitorControl),
[Notchy HUD page](https://notchy.dev/mac-volume-hud/),
[MacRumors forum on Tahoe HUD](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/).

---

## 5. Battery (§4 of brief) — Grade A

```swift
import IOKit.ps
func readBattery() -> (percent: Int, charging: Bool, onAC: Bool, minutesLeft: Int?)? {
  guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
        let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
  for ps in list {
    guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
          (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
    let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
    let charging = d[kIOPSIsChargingKey] as? Bool ?? false
    let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    let t = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int   // minutes; -1 = calculating
    return (cur * 100 / max, charging, onAC, (t ?? -1) >= 0 ? t : nil)
  }
  return nil
}
let src = IOPSNotificationCreateRunLoopSource({ _ in /* re-read + publish */ }, nil).takeRetainedValue()
CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
```

- **Low Power Mode:** `ProcessInfo.processInfo.isLowPowerModeEnabled` plus `NSNotification.Name.NSProcessInfoPowerStateDidChange`. **[VERIFIED: reads `true` on this Mac.]**
- **Adapter wattage:** `IOPSCopyExternalPowerAdapterDetails()` returns `kIOPSPowerAdapterWattsKey` ("Watts").
- **"Plugged in but not charging"** (Optimized Charging or a charge limit): `onAC && !charging && !isCharged`. Show "On hold".
- **Health and cycle count:** IORegistry `AppleSmartBattery` properties (`CycleCount`, `Temperature`, …). This is a public IOKit read with no permission.
- No entitlements are needed. The Mach port run-loop source fires on plug, unplug and percent changes.

**Sources:** boring.notch `BatteryActivityManager` (IOPS pattern); IOKit `IOPSKeys.h` / `IOPowerSources.h` in the macOS 27 SDK **[VERIFIED keys]**.

---

## 6. Calendar and Reminders (§5 of brief) — Grade A

```swift
import EventKit
let store = EKEventStore()
guard try await store.requestFullAccessToEvents() else { return }          // macOS 14+
let start = Date.now, end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
  .filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
if try await store.requestFullAccessToReminders() {
  store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)) { r in /*…*/ }
}
NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in /* reload */ }
```

- **Info.plist (required, or the request is silently denied with no prompt):**
  - `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`.
  - Keep the legacy `NSCalendarsUsageDescription` / `NSRemindersUsageDescription` if you target macOS 13.
  - SwiftBar PR #549 (merged 2026-09-26) is a live example of the missing-key failure. It also shows that TCC attributes a child process's request to the *responsible* app, so helpers inherit the parent app's keys.
- **Hardened runtime:** add `com.apple.security.personal-information.calendars`. Without it, a hardened app is denied. No sandbox entitlement is needed when unsandboxed.
- **Status check:** `EKEventStore.authorizationStatus(for: .event) == .fullAccess`. `.writeOnly` exists on macOS 14+.
- **Useful extras:** `EKEvent.structuredLocation`, meeting URL detection by regex on `url` / `notes` / `location` (Zoom, Meet, Teams), and `EKEvent.calendar.cgColor`.

**How to ship an Info.plist with SPM (no Xcode):**
- SwiftPM cannot produce `.app` bundles. Keep `Support/Info.plist` in the repo and have `scripts/bundle.sh` copy it to `Contents/Info.plist`. Stamp the version with `PlistBuddy -c "Set :CFBundleVersion $BUILD"`. See §17.
- For the bare-executable dev loop (`swift run`), you can embed a plist into the Mach-O: `linkerSettings: [.unsafeFlags(["-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__info_plist","-Xlinker","Support/Info.plist"])]`. However, TCC attributes prompts from `swift run` to Terminal (the responsible process), so **test permissions only from the assembled `.app`**.

**Sources:**
[TN3153 EventKit changes](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos),
[requestFullAccessToEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)),
[SwiftBar PR #549](https://github.com/swiftbar/SwiftBar/pull/549),
[Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).

---

## 7. Notification mirroring (§6 of brief) — Grade C (AX) / D (DB)

There is **no public API** to read other apps' notifications.

| Option | How | Permission | Notes |
|---|---|---|---|
| **AX observation of Notification Center UI** | Get the PID of `com.apple.notificationcenterui` and create `AXUIElementCreateApplication(pid)`. Call `AXObserverCreate` and add `kAXWindowCreatedNotification`, `kAXCreatedNotification`, `kAXUIElementDestroyedNotification`, and "AXChildrenChanged" / "AXLayoutChanged". Walk the banner subtree for `AXStaticText` values (app name, title, body). | **Accessibility** | boring.notch merged this on 2026-09-25 (PR #1617): event-driven instead of 0.5 s polling. It covers subroles `AXNotificationCenterNotification`, `AXNotificationCenterBannerWindow` and `AXNotificationCenterAlertStack`. It strips bidi control characters and maps helper bundle IDs (for example `com.google.Chrome.helper`) to the parent app. It only sees notifications that are **shown as banners** (not Focus-suppressed, not style "None"). Fragile across OS updates, and #1577 reports duplicate triggers when the sidebar opens. |
| **Read the usernoted SQLite DB** | Sequoia+ path: `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (moved there in macOS 15). The `record` table has a binary-plist `data` blob with app, title, subtitle and body. Watch the `-wal` file with `DispatchSource` / FSEvents. | **Full Disk Access** **[VERIFIED blocked without FDA on 27.0.1]** | Undocumented schema that changes between releases. Apple moved it on purpose to protect Messages content. Asking for FDA is a big trust ask. |
| **Per-service APIs** | Slack (Web API or Socket Mode with a user or app token), GitHub notifications API, Gmail API, Discord bot, and so on | OAuth tokens | Reliable but heavy. Better delivered as optional plugins on the §16 API. |
| **iMessage** | `~/Library/Messages/chat.db` | FDA | Same trust problem. Not recommended. |
| **Push API (ours)** | Scripts, CI and apps push to the notch (§16) | none | **Primary path.** |

**Recommendation:**
- Make the push API first-class.
- Offer an **opt-in, clearly labelled "experimental" AX mirror** that reuses the Accessibility grant already needed for HUD suppression.
- Do not ship an FDA-based reader by default. If you do add one, make it a separate opt-in with a plain-language privacy explanation.

**Sources:**
[boring.notch PR #1617](https://github.com/TheBoredTeam/boring.notch/pull/1617),
[boring.notch #1577](https://github.com/TheBoredTeam/boring.notch/issues/1577),
[Csaba Fitzl on the DB move](https://x.com/theevilbit/status/1811758367045537990),
[9to5Mac Security Bite](https://9to5mac.com/2024/09/01/security-bite-apple-addresses-privacy-concerns-around-notification-center-database-in-macos-sequoia/),
[notify-relay (DB relay example)](https://github.com/daniphant/notify-relay),
[DFIR notes on the DB](https://forge-work.com/dfir/knowledge/artifacts/macos-notification-center).

---

## 8. File shelf, AirDrop, Quick Look (§7 of brief) — Grade A

- **Drop target:** register the content view with `registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])` and implement `NSDraggingDestination` (`draggingEntered`, `performDragOperation`). SwiftUI's `.onDrop(of: [.fileURL], …)` also works inside `NSHostingView`.
  - The panel must accept drags while non-key; a non-activating panel is fine.
  - Auto-expand when a drag starts anywhere by using the drag-pasteboard `changeCount` trick (§3.2).
- **Persisting items:**
  - Unsandboxed apps can store plain file paths.
  - Prefer `URL.bookmarkData(options: [.withSecurityScope])` or at least plain bookmarks, so files survive renames and moves. Resolve with `URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`.
  - Security-scoped bookmarks are only *required* when sandboxed. The `com.apple.security.files.bookmarks.app-scope` entitlement in boring.notch exists because it is sandboxed.
  - Copy items dropped from Photos or other promise providers (`NSFilePromiseReceiver`) into `~/Library/Application Support/<App>/Shelf/`.
- **AirDrop:** `NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)`. Check `canPerform(withItems:)` first. For the full share menu, use `NSSharingServicePicker(items:)`. Both are public, with no entitlement.
- **Thumbnails:**
  - `QLThumbnailGenerator.shared.generateBestRepresentation(for: QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: screen.backingScaleFactor, representationTypes: .all))`.
  - Use `NSWorkspace.shared.icon(forFile:)` as the instant placeholder.
  - Quick Look preview: `QLPreviewPanel.shared()` (needs a responder chain, so temporarily make the panel key) or `qlmanage -p` as a fallback.
- **Drag out:** `NSItemProvider(contentsOf:)` / `.onDrag` or `NSDraggingSource` with file URLs.

**Sources:** boring.notch Shelf services (`QuickShareService`, `ThumbnailService`, `DragDetector`); NotchDrop TrayDrop (MIT).

---

## 9. Bluetooth devices and AirPods battery (§8 of brief) — Grade C (AirPods) / B (Magic devices)

- **Connection events (public IOBluetooth):**
  - `IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))`.
  - In the connected handler, call `device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))`.
  - `IOBluetoothDevice.pairedDevices()`, `isConnected()`, `name`, `deviceClassMajor`.
- **AirPods and Beats battery (private KVC on IOBluetoothDevice):** `batteryPercentSingle`, `batteryPercentLeft`, `batteryPercentRight`, `batteryPercentCase`, `batteryPercentCombined`.
  - **Guard with `responds(to: Selector("batteryPercentLeft"))` before `value(forKey:)`**, or a missing key throws `NSUndefinedKeyException` and crashes.
  - 0 means "not reported", not "empty".
  - The case value only appears while the case is open and connected.
  - Refresh on connect, on menu open, and every 30–60 s.
- **Magic Keyboard / Mouse / Trackpad:** IORegistry property `BatteryPercent` on HID services (`ioreg -r -k BatteryPercent`). Read with `IOServiceGetMatchingServices` plus `IORegistryEntryCreateCFProperty`. This is public IOKit and needs no permission.
- **Fallback:** `system_profiler SPBluetoothDataType -json` has `device_batteryLevelLeft`, `device_batteryLevelRight` and `device_batteryLevelCase`. It is slow (about 1–2 s), so run it off-main and rarely.
- **Nearby AirPods before they connect:** parse the Apple manufacturer data (company 0x004C, proximity-pairing type 0x07) in CoreBluetooth advertisements, as OpenPods-style apps do. This is reverse-engineered and changes with firmware.
- **iPhone battery:** no API (Continuity is private). boring.notch #1614 is an open feature request for it.
- **Permissions:**
  - IOBluetooth and CoreBluetooth are TCC-gated (Bluetooth) on modern macOS [REPORTED]. Add `NSBluetoothAlwaysUsageDescription`.
  - The first call can block until the prompt is answered, so call it off the main thread.
  - `com.apple.security.device.bluetooth` is only for sandboxed apps.

**Sources:**
[airflow PR #6 (KVC keys)](https://github.com/cpunion/airflow/pull/6),
[simple-battery](https://github.com/AdamMackey/simple-battery),
[IOBluetooth connect-notification forum thread](https://developer.apple.com/forums/thread/738748),
[device-battery #8 (case caching)](https://github.com/evanpersinger/device-battery/issues/8),
[Raycast airpods-battery extension](https://github.com/raycast/extensions/pull/29160),
[boring.notch #1614](https://github.com/TheBoredTeam/boring.notch).

---

## 10. Downloads progress and capture indicators (§9 of brief)

### 10.1 Downloads — Grade B

`+[NSProgress addSubscriberForFileURL:withPublishingHandler:]` (Swift: `Progress.addSubscriber(forFileURL:withPublishingHandler:)`) is **not deprecated**. It is macOS 10.9+ and still declared in the macOS 27 SDK **[VERIFIED header]**. The header says the handler fires for a progress whose `NSProgressFileURLKey` is "the same as this method's URL, or that is an item that the URL directly contains". So **subscribing to `~/Downloads` catches downloads directly in that folder**.

```swift
let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
let token = Progress.addSubscriber(forFileURL: downloads) { progress in
  // progress is a proxy: observe fractionCompleted, fileURL, estimatedTimeRemaining via KVO
  let obs = progress.observe(\.fractionCompleted) { p, _ in /* update notch */ }
  return { _ = obs /* unpublished: finished or cancelled */ }
}
// Progress.removeSubscriber(token) on teardown
```

- Browsers that publish (Safari, and Chrome per Finder's progress-bar behaviour) appear here. Verify each browser; Firefox is uncertain.
- The handler runs on the main thread.
- **Fallback:** watch `~/Downloads` for `*.download`, `*.crdownload` and `*.part` with `DispatchSource.makeFileSystemObjectSource` or FSEvents. Note that **listing `~/Downloads` triggers the "Downloads Folder" TCC prompt** for a non-sandboxed app. The subscription API may not; test it.
- **Publish your own** (for example for file-shelf copies or AirDrop): set `progress.kind = .file`, `fileOperationKind = .downloading`, and `fileURL`, then call `publish()`.

### 10.2 Mic and camera in use — Grade A **[VERIFIED readable without prompts]**

- **Mic, per app (macOS 14.2+):**
  - Enumerate `kAudioHardwarePropertyProcessObjectList` on the system object.
  - For each process object, read `kAudioProcessPropertyIsRunningInput` (UInt32), `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyPID`.
  - Listen for `kAudioDevicePropertyDeviceIsRunningSomewhere` ('gone') on input devices and for changes to the process list.
  - CoreAudio fires these listeners in bursts ("9+ callbacks per second"), so **dedupe and debounce**.
  - Map helpers (Chrome helper, WebKit) to parent apps.
  - Exclude your own PID.
- **Camera:**
  - Enumerate `kCMIOHardwarePropertyDevices` and read `kCMIODevicePropertyDeviceIsRunningSomewhere` per device.
  - Listen with `CMIOObjectAddPropertyListenerBlock`. On some macOS 12 builds the listener fired spuriously, so re-read the value before acting.
  - There is **no public per-process camera attribution**.
- The dwarvesf/hidden PR #438 (macOS 27) uses exactly these two public APIs: "a hardened, unentitled app without mic permission still saw a live recording".

### 10.3 Screen recording in progress — Grade D

- There is no public API. Apple shows a purple indicator in the menu bar and Control Center.
- **Heuristics:**
  - The built-in recorder has an open `.mov` in `~/Library/ScreenRecordings/` held by the `screencap` process (`lsof -c screencap`).
  - `CGWindowListCopyWindowInfo` can reveal Control Center indicator windows. Both are fragile.
- **Recommendation:** skip it, or offer it as an explicitly experimental option.

**Sources:**
[CoreAudio process objects article](https://macnotetaker.com/blog/which-app-is-using-mic-coreaudio-process-objects),
[hidden PR #438 (macOS 27)](https://github.com/dwarvesf/hidden/pull/438),
[kCMIODevicePropertyDeviceIsRunningSomewhere](https://developer.apple.com/documentation/coremediaio/kcmiodevicepropertydeviceisrunningsomewhere),
[CMIO listener quirk on macOS 12](https://developer.apple.com/forums/thread/697124),
[macos-screen-recording-detect](https://github.com/TomasHubelbauer/macos-screen-recording-detect),
[Apple forum: screen recording detect](https://developer.apple.com/forums/thread/773613),
[go-macos/fileprogress (publishing file progress)](https://github.com/go-macos/fileprogress).

---

## 11. Focus / Do Not Disturb, and Shortcuts (§10 of brief)

### 11.1 Focus detection

| Approach | Status on macOS 27 | Grade |
|---|---|---|
| `INFocusStatusCenter.default.focusStatus.isFocused` | Only a Bool ("is the user focused", from your app's perspective). Needs the **Communication Notifications entitlement** plus `NSFocusStatusUsageDescription`. A `com.apple.developer.*` entitlement needs a provisioning profile, so it is **impossible for ad-hoc builds** and questionable for Developer ID. | D |
| `~/Library/DoNotDisturb/DB/Assertions.json` + `ModeConfigurations.json` | Gives the mode ID and name. **TCC-protected; needs FDA [VERIFIED "Operation not permitted"].** One crate claims no FDA is needed; our test contradicts that. Watch the file with `DispatchSource` after FDA is granted. | C |
| Distributed `_NSDoNotDisturbEnabledNotification` / `…Disabled…` | **Reportedly no longer posted on macOS 27** (Atoll #632: "I checked with a listener while toggling Do Not Disturb and nothing arrived"). | D |
| `log stream` on `duetexpertd` lines (`semanticModeIdentifier`, `starting: 1/0`) | Works for now without permissions (Atoll's "dev tools" mode). Parsing unified-log text is brittle. | C |
| **Shortcuts Personal Automations**: "When <Focus> turns on/off" → *Open URL* `notch://focus?mode=Work&state=on` | Public and robust. Needs one-time user setup; ship importable `.shortcut` files signed with `shortcuts sign`. | **B** |
| On-demand: a user-installed shortcut using the "Get Current Focus" action, run via `shortcuts run "Notch – Current Focus" -o -` | Public, but slow (hundreds of ms) and needs the shortcut installed | B |

**Recommendation:** use the Shortcuts bridge by default, with an optional FDA-based reader for power users. Also ship a small `Focus` activity in the push API so that Hammerspoon, BetterTouchTool and similar tools can report it.

### 11.2 Shortcuts integration

- **Run shortcuts from the notch:** `Process` with `/usr/bin/shortcuts run "<name>" [-i <input-path>] [-o <output-path>] [--output-type <UTI>]`, and `shortcuts list` to populate a picker **[VERIFIED CLI on 27.0.1]**. The URL form `shortcuts://run-shortcut?name=<n>&input=text&text=<t>` also works; `x-callback-url` variants support returning a result.
- **Expose the app to Shortcuts via App Intents: not feasible with CLT.** Xcode runs `appintentsmetadataprocessor` to extract `Metadata.appintents` into the bundle, and that tool is **absent from CLT [VERIFIED]**. Without that metadata, Shortcuts will not discover the intents.
- **Workarounds Shortcuts can call today:**
  - The **URL scheme** ("Open URLs" action).
  - **AppleScript** ("Run AppleScript") against our `sdef` (§16).
  - **Shell** ("Run Shell Script" → the bundled `notchctl` CLI).
- Macros, snippets and Mac Catalyst-style tricks don't help here.

**Sources:**
[Atoll #632](https://github.com/Ebullioscopic/Atoll/issues/632),
[getfocus](https://github.com/davidolrik/getfocus),
[macos-focus](https://github.com/eugenehp/macos-focus),
[JXA focus gist](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18?permalink_comment_id=4413559),
[INFocusStatusCenter](https://developer.apple.com/documentation/intents/infocusstatuscenter?language=objc),
[Focus status API forum](https://developer.apple.com/forums/thread/682143),
[appintentsmetadataprocessor (Marc Palmer)](https://marcpalmer.net/changes-in-app-intents-pre-processing-causing-confusing-errors-in-xcode-16/),
[rules_apple #3090](https://github.com/bazelbuild/rules_apple/issues/3090).

---

## 12. Webcam mirror (§11 of brief) — Grade A

```swift
import AVFoundation; import SwiftUI
final class CameraController {
  let session = AVCaptureSession(); private let q = DispatchQueue(label: "camera")
  func start() {
    q.async { [session] in
      guard let dev = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                                                        mediaType: .video, position: .unspecified).devices.first,
            let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return }
      session.beginConfiguration(); session.sessionPreset = .medium; session.addInput(input); session.commitConfiguration()
      session.startRunning()
    }
  }
  func stop() { q.async { [session] in session.stopRunning(); session.inputs.forEach(session.removeInput) } }
}
struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession
  func makeNSView(context: Context) -> NSView {
    let v = NSView(); v.wantsLayer = true
    let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill
    layer.connection?.automaticallyAdjustsVideoMirroring = false; layer.connection?.isVideoMirrored = true
    v.layer = layer; return v
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- **Permission:** `AVCaptureDevice.requestAccess(for: .video)`.
  - Info.plist needs `NSCameraUsageDescription`.
  - Hardened runtime needs `com.apple.security.device.camera`; without it the camera is silently denied.
- **Ad-hoc TCC churn:** grants are keyed to the code signature's designated requirement. An ad-hoc DR is `cdhash H"…"`, so **every rebuild or update is a new app** and the user is re-prompted (and Accessibility grants silently stop working). Fixes are in §17.3.
- Tear down the session when collapsed so the green LED turns off.
- Don't poll `authorizationStatus` in a loop. boring.notch PR #1608 fixed a "camera authorization refresh loop pegging a CPU core".

**Sources:** boring.notch `WebcamManager` and PR #1615/#1608; [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime); the TCC/cdhash issues cited in §17.

---

## 13. Weather (§12 of brief) — Grade A

- **WeatherKit** needs the `com.apple.developer.weatherkit` entitlement, an App ID and a paid membership. The REST variant needs a JWT signed with a developer key, which cannot be shipped in an open-source client. **Not viable.**
- **Open-Meteo** (no API key):
  - `GET https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m&hourly=temperature_2m,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto`
  - Geocoding: `GET https://geocoding-api.open-meteo.com/v1/search?name=<city>&count=5`
  - Terms: the free tier is for **non-commercial** use, with limits of 600/min, 5,000/h, 10,000/day and 300,000/month. Data is **CC BY 4.0**, so show "Weather data by Open-Meteo.com". A free, ad-free open-source app fits their non-commercial examples. Cache for 15–30 min.
  - Map WMO `weather_code` to SF Symbols.
- **Alternatives:** MET Norway `api.met.no` (free; requires an identifying `User-Agent`) and NWS `api.weather.gov` (US only).
- **Location:**
  - `CLLocationManager` with `requestWhenInUseAuthorization()` and `requestLocation()`.
  - Info.plist: `NSLocationUsageDescription` (macOS) plus `NSLocationWhenInUseUsageDescription`.
  - Hardened runtime: `com.apple.security.personal-information.location`. Without it the prompt is suppressed.
  - Agent apps (`LSUIElement`) sometimes don't show the prompt until `requestLocation()` is called.
  - Always offer a **manual city** fallback. Round coordinates to about 0.1° before sending them to the API.

**Sources:**
[Open-Meteo terms](https://open-meteo.com/en/terms),
[Apple forum: no location prompt on macOS](https://developer.apple.com/forums/thread/756497),
[status-trio PR #55 (location entitlement fix)](https://github.com/lingyired/status-trio/pull/55),
[Apple forum: location on macOS](https://developer.apple.com/forums/thread/84315).

---

## 14. Clipboard history (§13 of brief) — Grade B

- **Detect changes:** poll `NSPasteboard.general.changeCount` every 0.5–1 s. It is cheap and does **not** trigger the privacy alert. There is no change notification API.
- **Pasteboard privacy (macOS 15.4 API, "macOS 16/26" rollout):**
  - `NSPasteboard.accessBehavior` has cases `.default`, `.ask`, `.alwaysAllow` and `.alwaysDeny`.
  - The 27.0 SDK header **[VERIFIED]** says: "The default behavior for the General pasteboard is to ask upon programmatic access". Once an app triggers the first alert, it is listed in System Settings, where the user can choose Ask, Always Allow or Deny.
  - Public reporting in mid-2026 says enforcement was announced but not on by default for everyone. **Design as if the alert exists.**
- **Mitigations:**
  - Use `detectPatterns(for:)`, `detectValues(for:)` and `detectMetadata(for:)` to classify content without reading it ("without notifying the person").
  - Read contents only when the user enables clipboard history, and tell them to pick "Always Allow".
  - Test with `defaults write <bundle-id> EnablePasteboardPrivacyDeveloperPreview -bool yes`.
- **Hygiene:** skip `org.nspasteboard.ConcealedType`, `TransientType` and `AutoGeneratedType` (password managers set these). Keep history in memory or encrypted. Add per-app exclusions using `NSWorkspace.shared.frontmostApplication` at change time.
- Tahoe also added a built-in Spotlight clipboard history, which reduces the value of this feature.

**Sources:**
[Michael Tsai: Pasteboard privacy preview](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/),
[NSPasteboard.AccessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum),
[9to5Mac](https://9to5mac.com/2025/05/12/macos-16-clipboard-privacy-protection/),
[Lapcat](https://lapcatsoftware.com/articles/2025/5/3.html),
[Paste blog on Tahoe clipboard](https://pasteapp.io/blog/macos-tahoe-clipboard-history).

---

## 15. System stats (§14 of brief) — Grade A (temperatures C)

- **CPU:**
  - `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)` gives per-core `cpu_ticks[CPU_STATE_USER|SYSTEM|IDLE|NICE]`. Diff two samples.
  - `vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * 4)` afterwards.
  - Aggregate: `host_statistics(…, HOST_CPU_LOAD_INFO, …)`.
  - Per-cluster P/E split: `sysctlbyname("hw.perflevel0.logicalcpu")` and `perflevel1`.
- **Memory:**
  - `host_statistics64(mach_host_self(), HOST_VM_INFO64, &vmstat, &count)` gives `free_count`, `active_count`, `inactive_count`, `wire_count`, `compressor_page_count`, `internal_page_count`. Multiply by `vm_kernel_page_size`.
  - Total: `ProcessInfo.processInfo.physicalMemory`.
  - Pressure: `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` or `sysctl kern.memorystatus_vm_pressure_level`.
- **Network:**
  - `getifaddrs` with AF_LINK `ifa_data` as `if_data` works, but `ifi_ibytes` / `ifi_obytes` are **32-bit and wrap at 4 GiB**.
  - Prefer `sysctl([CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0])` and parse `if_msghdr2` for 64-bit counters.
  - Use `NWPathMonitor` for the interface and connectivity state.
- **Disk:** `URLResourceValues.volumeAvailableCapacityForImportantUsage`.
- **GPU:** IORegistry `IOAccelerator` → `PerformanceStatistics["Device Utilization %"]`. No permission needed.
- **Thermals:**
  - Public: `ProcessInfo.thermalState` (coarse).
  - Real temperatures on Apple Silicon: private `IOHIDEventSystemClientCreate` with temperature-sensor services (exelban/stats `Modules/Sensors/reader.m`, MIT), or the AppleSMC user client (`IOServiceOpen("AppleSMC")`, chip-specific keys).
  - `powermetrics` needs root, so it is not an option.
  - Label temperatures "experimental".

**Sources:** [exelban/stats (MIT)](https://github.com/exelban/stats) (Sensors reader uses `IOHIDEventSystemClientCreate`); Mach headers in the SDK.

---

## 16. Extensibility: "maximum integrations" (§15 of brief) — Grade A

### 16.1 What comparable projects do

| Project | Transport | Auth | Notes |
|---|---|---|---|
| notchPulse (proprietary) | HTTP `POST 127.0.0.1:7842/event`, JSON `{event: start\|progress\|update\|complete\|fail, id, title, source, detail, progress 0–1, tokens, cost, app, …}` | none | Network.framework with a custom minimal HTTP parser. Ships a Claude Code hook script that "exits 0 always (never blocks)". |
| Notchy | HTTP `127.0.0.1:9999` | **per-install token**, off by default | "scripts, CI, or menu-bar tools render their own live activity and notification islands" |
| Vibe Notch / Claude Island (Apache-2.0) | Hook scripts in `~/.claude/hooks/` → **Unix socket** | — | Approve and deny permission requests from the notch. **Security bug:** the socket at `/tmp/claude-island.sock` was 0777, so any process could forge events. |
| boring.notch PR #1606 (open) | Authenticated loopback requests from Claude Code and OpenClaw hooks | token | Needed to **drop the app sandbox** to read session files and install hooks. |
| boring.notch PR #1629 (open) | `.bnplugin` **in-process C-ABI plugins** | Developer ID Team-ID approval | Requires `disable-library-validation`; plugins share the host's permissions. Heavy trust model. |
| SwiftBar / xbar | Executable scripts that print a text DSL on an interval | filesystem | The simplest third-party extension model. |
| Hammerspoon / BetterTouchTool / Raycast | URL schemes (`hammerspoon://`, `btt://`, `raycast://`), AppleScript, a local webserver (BTT) | varies | — |

### 16.2 Recommended architecture: one `ActivityHub`, many thin transports

**Canonical model** (versioned JSON, `schema: 1`):

```json
{ "schema": 1, "id": "ci-1234", "source": "github-actions", "kind": "progress",
  "title": "Deploy web", "subtitle": "step 3/5", "icon": {"sfSymbol": "shippingbox"},
  "tint": "#34C759", "progress": 0.6, "state": "running",
  "ttl": 600, "priority": "normal", "sticky": false,
  "actions": [{ "id": "open", "label": "Open run", "url": "https://github.com/…" },
              { "id": "approve", "label": "Approve", "reply": true }] }
```

- **Operations:** `upsert`, `patch`, `end(state: success|failure|cancelled)`, `dismiss`, `list`, `subscribe`.
- **Kinds:** `progress`, `status`, `alert`, `timer`, `nowPlaying` (external players), `approval` (blocking reply), `hud`.

**Transports, all mapping into the hub:**

1. **Unix-domain socket, HTTP/1.1** at `~/Library/Application Support/<App>/api.sock`.
   - The directory is 0700 and the socket 0600. Filesystem permissions are the authentication.
   - No firewall prompts and no port collisions.
   - `curl --unix-socket … http://localhost/v1/activities -d @payload.json`.
   - Implement with `Network.framework` `NWListener(using: .tcp)` on `NWEndpoint.unix(path:)`, or with a BSD socket plus `DispatchSource`.
2. **Optional loopback TCP**, off by default: `127.0.0.1:<port>`, `Authorization: Bearer <token>` read from `~/Library/Application Support/<App>/token` (0600).
   - For tools that can't use UDS: Stream Deck plugins, browser extensions (WebSocket), Home Assistant through SSH or a reverse tunnel.
   - Also expose `GET /v1/events` as SSE or a WebSocket for approvals and action callbacks.
   - Loopback does not trigger macOS 15+ *Local Network* privacy. Binding to LAN (for Home Assistant on another host) does, and needs a token plus an explicit opt-in.
3. **Bundled CLI `notchctl`** in `Contents/Helpers/`, a second SwiftPM executable target. Offer "Install CLI" to symlink it into `~/.local/bin` or `/usr/local/bin`.
   - `notchctl activity start --id build --title "Build" --progress 0.1`
   - `notchctl activity end --id build --state success`
   - `notchctl ask --title "Allow rm -rf?" --timeout 60`: blocks and exits 0 or 1.
4. **URL scheme** (`CFBundleURLTypes`): `notch://activity/start?id=…&title=…`, `notch://focus?mode=Work&state=on`, `notch://open/shelf`.
   - Handle in `application(_:open:)`. Callers use `open -g` so the app is not brought forward.
   - Reach for Shortcuts, Raycast/Alfred deep links and BetterTouchTool.
5. **AppleScript / JXA:** Info.plist `NSAppleScriptEnabled = YES`, `OSAScriptingDefinition = Notch.sdef` (a plain XML file in Resources). Implement `NSScriptCommand` subclasses. This works without Xcode, and is how Keyboard Maestro and Shortcuts' "Run AppleScript" integrate.
6. **Fire-and-forget signals:**
   - Darwin notify: `notifyutil -p com.example.notch.refresh`, observed with `notify_register_dispatch`.
   - `DistributedNotificationCenter` for Cocoa clients. Unsandboxed apps can send userInfo; don't rely on it from sandboxed senders.
7. **Script plugins** (SwiftBar-style), in `~/Library/Application Support/<App>/Plugins/*.{sh,py,js}`.
   - Metadata in header comments (`# notch.refresh: 30s`); the script prints hub JSON to stdout.
   - Run with a timeout. Isolated: no in-process code, no `disable-library-validation`.
8. **Later, optional:** JavaScriptCore plugins (`JSContext`) with a narrow bridged API, if richer UI logic is ever needed. **Avoid in-process dylib plugins.**

**Ready-made recipes to document:**
- **Claude Code hooks:** `~/.claude/settings.json` → `hooks` for `Notification`, `Stop`, `PreToolUse` and `SessionStart` events, each running `notchctl …`. Hook input JSON arrives on stdin.
  - For approvals, use a blocking `notchctl ask` in a permission-related hook. Fail open to Claude Code's native prompt on timeout, as boring.notch #1606 does.
- **GitHub Actions / CI:** a self-hosted runner, or a local `gh run watch` wrapper posting progress.
- **Hammerspoon:** `hs.execute("notchctl …")` or `hs.urlevent.openURL("notch://…")`.
- **Raycast / Alfred:** script commands calling `notchctl`.
- **BetterTouchTool:** "Open URL" action.
- **Stream Deck:** "Website" or "System: Open" action with the URL scheme.
- **Home Assistant:** `rest_command` to the token-protected TCP endpoint, or `shell_command` over SSH.

**Security checklist:**
- Never create sockets in `/tmp` or with 0777 permissions.
- Rate-limit clients and cap payload size (for example 64 KB).
- Validate `schema`.
- Sanitize text; no HTML.
- Only open action URLs with allow-listed schemes.
- Show the `source` label on every activity so spoofing is visible.

**Sources:**
[notchPulse](https://github.com/lakshaymeghlan/notchPulse),
[Notchy](https://notchy.dev/),
[Vibe Notch](https://github.com/farouqaldori/vibe-notch),
[Vibe Notch README](https://github.com/farouqaldori/vibe-notch/blob/main/README.md),
[notchi](https://github.com/sk-ruban/notchi),
[boring.notch PR #1606](https://github.com/TheBoredTeam/boring.notch/pull/1606),
[boring.notch PR #1629](https://github.com/TheBoredTeam/boring.notch/pull/1629),
[Raycast Hammerspoon extension](https://www.raycast.com/bjrmatos/hammerspoon).

---

## 17. Packaging, signing, updates and testing without Xcode (§16 of brief)

### 17.1 What CLT can and cannot do **[VERIFIED]**

- **Available:** `swift build` / `swift test`, `codesign`, `notarytool`, `stapler`, `plutil`, `PlistBuddy`, `iconutil`, `lipo`, `ditto`, `hdiutil`, `security`.
- **Missing:**
  - `actool`: no Assets.car and no macOS 26 Icon Composer `.icon`. Ship a classic `.icns` built with `iconutil` and set `CFBundleIconFile`. Tahoe may show non-conforming legacy icons inside a grey rounded-rect.
  - `ibtool`: no XIBs; that's fine with SwiftUI and code-only AppKit.
  - `xcstringstool`: String Catalogs won't compile. Use `.strings` / `.stringsdict`, or `Localizable.xcstrings` compiled elsewhere.
  - `momc`: no Core Data models; use SwiftData or SQLite.
  - `appintentsmetadataprocessor`: no App Intents.
  - `sdef` / `sdp`: no ScriptingBridge header generation.
  - **XCTest.**

### 17.2 Bundle assembly script (outline)

```bash
#!/usr/bin/env bash
set -euo pipefail
APP="build/Notch.app"; ID="dev.example.notch"; SIGN="${SIGN_IDENTITY:--}"   # "-" = ad-hoc
swift build -c release --arch arm64            # add --arch x86_64 for universal
BIN="$(swift build -c release --show-bin-path)"   # new build system: .build/out/Products/Release
rm -rf "$APP"; mkdir -p "$APP/Contents/"{MacOS,Resources,Frameworks,Helpers}
cp "$BIN/Notch" "$APP/Contents/MacOS/Notch"
cp "$BIN/notchctl" "$APP/Contents/Helpers/notchctl"
cp Support/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
cp -R "$BIN"/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true   # Bundle.module looks in resourceURL first
cp Vendor/mediaremote-adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"
ditto Vendor/mediaremote-adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
[ -d "$BIN/Sparkle.framework" ] && ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
plutil -lint "$APP/Contents/Info.plist"

# Sign inside-out (never --deep). Release: SIGN="Developer ID Application: …", add --options runtime --timestamp
OPTS=(--force --sign "$SIGN"); [ "$SIGN" != "-" ] && OPTS+=(--options runtime --timestamp)
codesign "${OPTS[@]}" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
# Sparkle nested code first: XPCServices/*.xpc, Autoupdate, Updater.app, then the framework
codesign "${OPTS[@]}" "$APP/Contents/Helpers/notchctl"
codesign "${OPTS[@]}" --entitlements Support/Notch.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
```

`Package.swift` must add the Frameworks rpath, because the default rpaths lack it **[VERIFIED]**:

```swift
.executableTarget(name: "Notch", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
  linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])
```

`unsafeFlags` are allowed in the root package.

**Info.plist essentials:**
- Bundle identity: `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleName`, `CFBundlePackageType=APPL`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion` (14.0 or later; see note), `LSUIElement=YES` (no Dock icon), `NSHighResolutionCapable=YES`, `CFBundleIconFile`.
- Usage descriptions: `NSAppleEventsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSCameraUsageDescription`, `NSLocationUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSBluetoothAlwaysUsageDescription`.
- Integrations: `CFBundleURLTypes`, `NSAppleScriptEnabled`, `OSAScriptingDefinition`, `SUFeedURL`, `SUPublicEDKey`.
- Note: `requestFullAccessToEvents` needs macOS 14; the process-object mic API needs 14.2.

**Entitlements** (Developer ID, hardened runtime, **unsandboxed**; no `com.apple.security.app-sandbox`):
- `com.apple.security.automation.apple-events`
- `com.apple.security.device.camera`
- `com.apple.security.personal-information.calendars` (EventKit)
- `com.apple.security.personal-information.location`
- Only if needed: `com.apple.security.device.audio-input`
- **Not** `cs.disable-library-validation`. The adapter framework loads into *perl*, not into our process.

For ad-hoc dev builds, skip `--options runtime`. Hardened runtime with an ad-hoc signature (no Team ID) complicates loading embedded frameworks such as Sparkle, and it isn't needed without notarization.

### 17.3 TCC stability with ad-hoc signing (important for Accessibility)

- An ad-hoc signature's designated requirement is `cdhash H"…"` **[VERIFIED]**. TCC stores grants against the DR, so **every rebuild or update silently invalidates** the Accessibility, Camera, Calendars and Automation grants. System Settings shows a stale checked entry, and `AXIsProcessTrusted()` returns false.
- **Fixes, best first:**
  1. **Developer ID Application** certificate ($99/yr). The DR becomes the Team ID plus the bundle ID, so grants persist and notarization becomes possible.
  2. A **self-signed code-signing certificate** in the login keychain (Keychain Access → Certificate Assistant). The DR becomes the identifier plus the certificate hash, which is stable for local and dev builds. Not accepted by Gatekeeper for others.
  3. **Ad-hoc with an explicit identifier DR:** `codesign -s - -r='designated => identifier "dev.example.notch"' App.app` **[VERIFIED signing works]**. Reported to keep grants across rebuilds after one re-prompt. The weaker security trade-off is that any binary with that identifier satisfies the DR. Use it for dev only.
- Detect a broken grant: when `AXIsProcessTrusted()` is false but the user says it's enabled, show "remove and re-add" instructions. Deep link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

### 17.4 Launch at login

- `SMAppService.mainApp.register()` / `.unregister()` / `.status` (`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`). Available on macOS 13+.
- One project reports **it works for an ad-hoc app on macOS 27**: `sfltool dumpbtm` shows `[enabled, allowed, notified]` (KlangLadder #7). Apple forum threads blame ad-hoc signing for "Operation not permitted" in other setups.
- **Fallback:** write `~/Library/LaunchAgents/dev.example.notch.plist` (`RunAtLoad`, `ProgramArguments` = the app executable, or `/usr/bin/open -a`), then run `launchctl bootstrap gui/$(id -u) <plist>`.
- Run from `/Applications`. App Translocation of quarantined apps breaks paths.

### 17.5 Auto-update (Sparkle 2)

- **SwiftPM:** `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.x")`. Sparkle is a binary XCFramework target; copy `Sparkle.framework` from the bin path into `Contents/Frameworks` and add the rpath (above). The docs, for non-Xcode builds: "add the flags `-Wl,-rpath,@loader_path/../Frameworks`". Preserve symlinks (`ditto`).
- **Code:** `let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`. Add a "Check for Updates…" menu item bound to `updater.checkForUpdates(_:)`.
- **Info.plist:** `SUFeedURL`, `SUPublicEDKey`, and a monotonically increasing `CFBundleVersion`.
- **Tools:** from the Sparkle release tarball's `bin/`: `generate_keys` (private key stored in the Keychain), `generate_appcast <updates_dir>`, and `sign_update`. Host the appcast on GitHub Pages or Releases.
- **Signing:** sign Sparkle's nested helpers (`Autoupdate`, `Updater.app`, XPC services) inside-out with the same identity. XPC services are only required for sandboxed apps.
- **With ad-hoc builds,** EdDSA protects update integrity, but **every update resets TCC grants** (§17.3). Strong argument for Developer ID once there are users.

### 17.6 Notarization (needs Developer ID; all tools present in CLT)

```bash
xcrun notarytool store-credentials notch --apple-id … --team-id … --password <app-specific>
ditto -c -k --keepParent build/Notch.app build/Notch.zip
xcrun notarytool submit build/Notch.zip --keychain-profile notch --wait
xcrun stapler staple build/Notch.app       # then build the DMG (hdiutil) and notarize/staple the DMG too
```

- **Requirements:** hardened runtime, a secure timestamp, no `get-task-allow`, and every nested Mach-O signed with the Developer ID. That includes `MediaRemoteAdapter.framework` and `notchctl`.
- **Without Developer ID:** users must clear quarantine (`xattr -dr com.apple.quarantine /Applications/Notch.app`), or use System Settings → Privacy & Security → "Open Anyway". Recent macOS removed the Finder right-click → Open bypass.
- Local copies and Homebrew keg copies have no quarantine xattr, so they launch without a Gatekeeper prompt (KlangLadder #7 on macOS 27).

### 17.7 Testing with CLT

- **XCTest: not available [VERIFIED].**
- **Swift Testing: available, but needs a flag on this toolchain [VERIFIED]:**

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

- Alternatively, put the flag in the test target (`swiftSettings: [.unsafeFlags(["-plugin-path", "<that path>"])]`) behind an environment check so Xcode or CI toolchains aren't affected.
- There is no XCUITest, so architect for testability:
  - Pure-Swift core modules: `ActivityHub`, adapter JSON diff-merge, geometry math, permission state machine, and the API router tested over a UDS in a temp dir.
  - Thin AppKit shells around them.
  - Small **probe executables** (like the ones in §0.1) as smoke tests that `scripts/doctor.sh` can run on a user's machine.

**Sources:**
[Sparkle documentation](https://sparkle-project.org/documentation/),
[Sparkle and code signing](https://swiftdevjournal.com/code-signing-and-the-sparkle-framework/),
[Christian Tietze on Sparkle XPC](https://christiantietze.de/posts/2019/06/sparkle-xpc-setup/),
[SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp),
[KlangLadder #7 (ad-hoc SMAppService on macOS 27)](https://github.com/janthoXO/KlangLadder/issues/7),
[Apple forum: SMAppService recovery](https://developer.apple.com/forums/thread/707482),
[Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime),
[TCC grants across rebuilds](https://github.com/tomada1114/macos-app-template/issues/61),
[hermes-agent identifier-pinned ad-hoc](https://github.com/NousResearch/hermes-agent/issues/121857),
[sunna: Accessibility prompt every launch](https://github.com/SunnyXdm/sunna/issues/1),
[theswiftdev: SPM-only macOS apps](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/),
[Swift Bundler](https://forums.swift.org/t/swift-bundler-create-macos-apps-with-swiftpm-instead-of-xcodeprojs/56790),
[Scott Willsey: shipping without opening Xcode](https://scottwillsey.com/building-and-shipping-mac-and-ios-apps-without-ever-opening-xcode/).

---

## 18. Liquid Glass (§17 of brief) — Grade A (use sparingly)

**API surface in the macOS 27 SDK [VERIFIED from the swiftinterface and headers]:**

- **SwiftUI (macOS 26+):**
  - `View.glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`.
  - `Glass.regular`, `.clear`, `.identity`, with `.tint(_:)` and `.interactive(_:)`.
  - `GlassEffectContainer { … }`.
  - Morphing: `.glassEffectID(_:in:)`, `.glassEffectUnion(id:namespace:)`, `.glassEffectTransition(_:)`.
  - `.buttonStyle(.glass)` / `.glassProminent` (`GlassButtonStyle`, `GlassProminentButtonStyle`).
  - `.backgroundExtensionEffect()`.
- **AppKit (macOS 26+):** `NSGlassEffectView` (`contentView`, `cornerRadius`, `tintColor`, `style: .regular/.clear`), with `effectIsInteractive` **new in macOS 27**, and `NSGlassEffectContainerView` (`spacing`).
- macOS 27 adds a **system-wide transparency slider** (Six Colors), so glass appearance now varies per user.

**Should a notch app use it?**

- **Closed or compact state: no.** It must be **pure black (#000)** to visually extend the hardware notch. Glass shows the wallpaper through it and breaks the illusion. boring.notch forces `.darkAqua` and a black shape for this reason.
- **Expanded state:** keep a black base, the de-facto "Dynamic Island" language. Use glass **inside** it for controls (buttons, chips, scrubber thumb) via `GlassEffectContainer`, and use `glassEffectID` morphs for a native feel.
- **Non-notch displays** (the virtual pill): an optional "Glass" theme is reasonable there, since there is no hardware to match.
- Always gate with `if #available(macOS 26, *)`.
- Respect `accessibilityReduceTransparency`; the system falls back automatically, but test your own tints.
- Avoid large continuously animating glass surfaces in an always-on overlay (GPU cost).

**Sources:** macOS 27 SDK `SwiftUICore.swiftinterface` / `NSGlassEffectView.h`; [Six Colors on macOS 27 transparency slider](https://sixcolors.com/post/2026/07/first-look-macos-golden-gate-public-beta/).

---

## 19. Permission and entitlement matrix

| Feature | TCC service | How requested | Info.plist key | Hardened-runtime entitlement |
|---|---|---|---|---|
| HUD suppression (event tap), media-key posting, AX notification mirror, terminal focus | Accessibility | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, `CGRequestPostEventAccess()` | — | — |
| Listen-only keyboard taps (not needed if Accessibility is granted) | Input Monitoring | `CGRequestListenEventAccess()` | — | — |
| Music, Spotify, browser AppleScript | Automation (per target) | first Apple Event / `AEDeterminePermissionToAutomateTarget` | `NSAppleEventsUsageDescription` | `automation.apple-events` |
| Calendar, Reminders | Calendars / Reminders | `requestFullAccessToEvents/Reminders` | `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription` | `personal-information.calendars` |
| Webcam | Camera | `AVCaptureDevice.requestAccess(for: .video)` | `NSCameraUsageDescription` | `device.camera` |
| Weather location | Location | `CLLocationManager.requestWhenInUseAuthorization()` | `NSLocationUsageDescription`, `NSLocationWhenInUseUsageDescription` | `personal-information.location` |
| AirPods and BT devices | Bluetooth | first IOBluetooth/CoreBluetooth use | `NSBluetoothAlwaysUsageDescription` | — |
| Clipboard history content | Paste (pasteboard privacy) | first programmatic read | — | — |
| Focus via files, notification DB | Full Disk Access | manual (Settings deep link `…?Privacy_AllFiles`) | — | — |
| Downloads-folder fallback watcher | Files & Folders: Downloads | first directory access | — | — |
| Now Playing (adapter or JXA), volume, battery, mic/camera-in-use, stats | **none** | — | — | — |

Design the onboarding so **the core app needs zero permissions**: notch, Now Playing, volume HUD alongside the system one, battery, stats, shelf and API. Each permission is then requested only when the user turns on the feature that needs it. CreativeNotch removed its HUD module precisely to reach "the app now requires no permissions at all".

---

## 20. Licensing notes for code reuse

| Project | License | Guidance |
|---|---|---|
| boring.notch, Atoll, BetterHUD, alt-tab-macos | **GPL-3.0** | Study the approaches, but **do not copy code** unless this project is GPL-3.0. |
| boring.notch `CGSSpace.swift` (from Parrot) | MPL-2.0 (file-level) | Reusable with the file-level copyleft kept. |
| NotchDrop, DynamicNotchKit, SkyLightWindow, MacroVisionKit, KeyboardShortcuts, exelban/stats, MonitorControl | MIT | Free to reuse with the notice kept. |
| ungive/mediaremote-adapter | BSD-3-Clause | Vendor with attribution. |
| ejbills/mediaremote-adapter | no license declared | Don't depend on it until licensed. |
| Sparkle | MIT-style (GitHub shows NOASSERTION because of bundled components) | Standard practice; include its LICENSE. |
| Vibe Notch | Apache-2.0 | Reusable with NOTICE. |
| Open-Meteo data | CC BY 4.0 | Attribution in the UI. |

---

## 21. Key risks to track

1. **The MediaRemote platform-binary loophole** (perl and osascript) is the single biggest dependency. Apple tightened access in 15.4 and could do it again. Keep the three-tier provider, health checks and kill-switches.
2. **HUD internals churn** in 27.x: the 27.2 beta brightness OSD change, and the macOS 26 HUD relocation.
3. **macOS 27 regressions seen in the wild:** display `localizedName` changes, DND distributed notifications gone, menu-bar layout changes. Use UUIDs, and treat undocumented signals as optional.
4. **Ad-hoc signing and TCC churn.** Every update loses Accessibility. Plan for Developer ID early.
5. **The pasteboard privacy rollout** may make clipboard history prompt-heavy.
