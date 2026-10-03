# Security

## Reporting a vulnerability

Issues are public, so please report security problems privately. Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and choose **Report a vulnerability**, or go straight to [the report form](https://github.com/aviralgarg05/islet/security/advisories/new). Only you and the maintainer can see the report.

Please include:

- the Islet version (*Settings → About*, or `isletctl health`) and the macOS version;
- what someone could do with the problem, and from where: another app on the Mac, a web page, another device on the network;
- steps, a request or a short script that shows it;
- any setting it depends on, such as the iPhone bridge being on.

Replies come in the advisory thread, on a best-effort basis. When a fix is released, the advisory is published and credits you, unless you'd rather not be named.

## Supported versions

Fixes go into the latest release only. Older versions don't get backports, so please update to the [latest release](https://github.com/aviralgarg05/islet/releases/latest).

## Security model

A short summary. The detail is in [Architecture: Local API security](docs/ARCHITECTURE.md#local-api-security) and [Privacy rules](docs/ARCHITECTURE.md#privacy-rules).

- **Local API.** It listens on loopback only, on port 47831 by default, and needs a bearer token from `api.json` (mode 0600) in `~/Library/Application Support/Islet`. The health check is the only request that works without it. The `Host` must be localhost and web-page origins are refused, which blocks DNS rebinding and cross-site requests. Header size, body size, slow connections, open connections and held long-polls are all capped.
- **iPhone bridge.** Off by default. When it's on, it is a second listener (port 47832) with its own token in `lan.json` (mode 0600). Each token works only on its own listener. The bridge accepts notifications, timers, Focus and simple activities and nothing else, limits each client to 30 requests per 10 seconds, and never answers approval requests.
- **`islet://` links** need no token, so they can do less: links must be https, icons can't be files or remote images, and priority tops out at high.
- **Network.** Islet has no account, telemetry or licence server. Data leaves the Mac only for things you set up or ask for: an Ask question to a cloud AI provider and that provider's model list, images you give Islet as URLs (drawn by SwiftUI, which uses the shared connection, cookie store and cache; every other request Islet sends keeps none of those), Spotify cover art when the system media bridge isn't running, and, once you turn them on, lyrics (a song's title, artist, album and length, to `lrclib.net`), the weather (a city name you type, or a position rounded to about a kilometre, to `open-meteo.com`), today's sales (to the stores you connect), stock prices (to Yahoo Finance, while the Stocks page is open) and AI usage (to OpenRouter and GitHub with the keys you paste). Apart from the pictures, none of these requests follows a redirect, so none of them can carry what it says to a host you didn't agree to.
- **Keys.** AI provider, store, OpenRouter and GitHub keys are kept in the login Keychain as generic passwords (service `dev.islet.Islet.ai`), readable only while the Mac is unlocked, and never in `config.json`, logs or child processes. What the Keychain lets read them depends on how the build is signed; see [Ad-hoc signing](#ad-hoc-signing) below. Each tool's requests go only to the hosts it names, over HTTPS, and redirects are refused so a key can't follow one. Islet never reads other apps' sign-in tokens.
- **Script widgets** run only if you own the script and its folder and nobody else can write to them. Islet shows a widget's command and asks before running it from a menu.

## Ad-hoc signing

Releases are ad-hoc signed and not yet notarised, so macOS can't tell a genuine copy from a modified one by its signature. Download Islet only from this repository's [Releases page](https://github.com/aviralgarg05/islet/releases). From 0.2.0 on, compare the zip with the SHA-256 in the release notes.

That signature carries no certificate. `scripts/bundle.sh` signs an ad-hoc build with a designated requirement of `identifier "dev.islet.Islet"` and nothing else, which is what lets macOS privacy grants (Accessibility, Calendars, Automation) survive a rebuild. It is also all the Keychain's default access list has to go on, so two things follow that a Developer ID would prevent:

- Another ad-hoc signed program that claims the identifier `dev.islet.Islet` satisfies the requirement, so it could read the saved provider, store, OpenRouter and GitHub keys without a prompt.
- A different bundle put where Islet is can inherit the privacy grants this Mac has already given Islet, by the same identifier check.

Signing with your own certificate ties both to it: `SIGN_IDENTITY="Developer ID Application: …" make app`. Nothing inside the app can close the gap. Moving the keys to the data-protection Keychain (`kSecUseDataProtectionKeychain`) wouldn't: it is a separate store, so keys saved by an earlier build would read as missing while sitting there unreachable, and on macOS it needs an application-identifier entitlement that an ad-hoc signature can't carry. An access list with no trusted application would prompt for every read, including the reads that happen while an answer streams.
