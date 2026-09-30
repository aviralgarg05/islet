# Contributing

Thanks for helping. A few ground rules keep Islet fast and trustworthy.

## Setup

Command Line Tools are enough (`xcode-select --install`). Then:

```bash
make test     # must pass
make e2e      # must pass (launches the app with an isolated config on its own port)
make perf     # must stay within budget
```

## Rules of the road

- **Decisions go in `IsletCore`**, as pure value types with an injected clock, and come with tests. `IsletSystem` only adapts macOS events to the core; the app layer only draws.
- **No polling while idle.** Use notifications, property listeners, file-system events or one deadline timer. Perpetual animations must be Core Animation layers, not SwiftUI `repeatForever`. `make perf` must stay green.
- **No new permission without an opt-in toggle** and a one-line reason in Settings. Nothing may prompt at launch.
- **Private APIs are capability-checked** (`dlsym`, weak linking, helper processes) so that removing them only disables that feature.
- **Clean-room code only.** Several notch apps are GPL-3.0; don't copy from them. MIT/BSD code is fine with attribution.
- **Match the surrounding style:** small files, doc comments on public types, no force-unwraps outside tests.

## Adding an integration

Prefer the existing surfaces (CLI, HTTP API, URL scheme, script widgets, agent hooks). If a new built-in source is needed:

1. Put the parsing and decision logic in `IsletCore` and test it.
2. Put the event source in `IsletSystem` behind a setting.
3. Add a recipe to `docs/INTEGRATIONS.md`, and a file to `integrations/` if the recipe needs one.
