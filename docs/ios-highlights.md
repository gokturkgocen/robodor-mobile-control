# iOS highlights

Built from zero in Swift / SwiftUI. The Android app was the original "golden contract" for device behaviour; the iOS port carries the same semantics with an idiomatic SwiftUI shell.

## Concurrency model

- Repository, telemetry store, and server bridges are all `@MainActor` classes. State is `@Published` and views observe via `@ObservedObject`.
- BLE I/O is serialised through async helpers wrapping `withCheckedContinuation`. Resume sites use a defensive capture pattern (capture continuation locally, nil the property, then resume) so re-entry can never resume the same continuation twice.
- A dedicated `RegisterPollingEngine` runs as a `Task` driven by adjustable polling speeds. Manual mode pauses normal polling and routes commands through a separate path with shorter timeouts.
- File persistence (telemetry history) snapshots data on the main actor and offloads JSON encode + atomic write to a `Task.detached(priority: .utility)` so polling cadence is never blocked by disk I/O.

## Auth + token refresh

- Cognito access + refresh token, with the access token automatically refreshed when within 60 s of expiry. Concurrent callers share one in-flight refresh `Task` so a burst of requests doesn't flood the server.
- Sessions persist in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). A first-launch migration moves any legacy `UserDefaults` session into the Keychain and removes the plain copy.
- Sign-out clears the queued telemetry buffer so events captured under the previous identity aren't flushed as the next user.

## Persistence resilience

- Telemetry history (session / 1h / 24h / 7d rolling buffers, downsampled at the right cadence per range) lives under `Application Support`, not `Caches`, so iOS cannot evict it under disk pressure. The directory is excluded from iCloud backup.
- A corrupt history file is **deleted** on read instead of looping the same decode error on every launch.
- A debounced 5-second save coalesces bursts of register updates into one write.

## UI / UX

- Custom `RDoorViz` component renders the door as 8 horizontal panels that lift / lower with the live `openPercentage`. Idle states draw a single static frame so the canvas isn't being repainted 60 fps for no reason.
- A live "→ %XX" pointer on the side scale tracks the door's position with a smooth `easeInOut` so the UI feels mechanical, not laggy.
- Charts screen consumes `TelemetryHistoryStore` so range tabs (Oturum / 1s / 24s / 7g) actually show different time windows from real persisted data, not synthetic placeholders.
- Per-tab polling speed and visible-register sets are switched on tab change so we don't poll registers we aren't displaying.
- Live Activity for the active door command (Dynamic Island + lock screen). App Shortcuts + custom URL scheme so Siri / a home-screen icon can launch a quick open / close.
- 5-language localisation (TR / EN / DE / FR / IT) covers everything user-facing including dynamic state labels for the door visualisation.

## Background behaviour

- `bluetooth-central` background mode declared so the connection survives a screen lock. Reconnect is suppressed when the app is backgrounded so we don't spin a reconnect storm against a sleeping radio.
- BLE quality metrics tracked continuously and surfaced on the dashboard top bar as a 4-bar indicator with hover-friendly latency tooltip.

## What touched what

The transport layer (CoreBluetooth wrapper, Modbus codec, CRC, polling engine) is intentionally untouched after the initial bring-up — its timeouts, MTU, and packet ordering are tuned by field testing and not subject to "code-quality" refactors. Defensive structural changes (continuation capture, persistence directory) are all on the orchestration layer above the transport.
