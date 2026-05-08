# Android highlights

The original platform — Android shipped first and is the reference implementation for device behaviour. The iOS app mirrors its semantics one-for-one.

## Architecture

- **Kotlin + Jetpack Compose + Hilt + KSP**. Single-activity app with a Compose navigation host.
- **Coroutines + StateFlow** end-to-end. `BleRepository` exposes hot `StateFlow`s for the connection state, register cache, and metrics; ViewModels collect and expose UI state.
- **Foreground service** (`RobodorBleService`) keeps the BLE session alive while the app is backgrounded with a persistent notification.
- **Modbus-over-BLE transport** through a commercial UART-to-BLE module with bonded pairing. The transport layer is treated as immutable post-tuning; refactors there are explicitly out-of-bounds.

## Settings system

A single Kotlin file (`SettingsRegisterSchema.kt`) describes every settings menu: which registers it owns, the read plan (start address + count), the codecs that pack / unpack values, the field validation rules, the localised labels. Adding a new menu is one block in that file — the screens, the persistence, the validation, and the BLE write all derive from the schema.

## Backup / snapshot

- Multiple named snapshots stored in SharedPreferences as a JSON array.
- Save: read every settings register live, encrypt with AES-GCM, write.
- Restore: select snapshot, pick which groups to restore (operator can restore "speed only" or "ramp + safety only"), the app fans out the writes to the device.
- Migration from the older single-snapshot format runs once, transparently, on first launch.

## BLE quality dashboard

`BleMetricsTracker` keeps a rolling 150-read latency window and an EMA. The dashboard top bar renders a 4-bar indicator in the same scheme as iOS (Excellent / Good / Weak / Critical) with the same thresholds.

## Localization

5 languages (TR / EN / DE / FR / IT) across `values/`, `values-en/`, `values-de/`, `values-fr/`, `values-it/`. Notification strings, error toasts, dynamic state labels — all localised. Language switch is persisted in `SharedPreferences` and applied via `LocaleHelper` with an Activity recreate.

## Theme

`RobodorColorPalette` data class with light + dark variants, accessed as `RobodorColors.X`. A monospace `RobodorMono` font for technical readouts (MAC addresses, latency values, register hex). Same token vocabulary as iOS so the two platforms feel like they came from the same design.
