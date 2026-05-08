# Design system

Both apps share one design language across SwiftUI and Compose. Tokens (colour, typography, radius, shadow, spacing) live behind named constants — never hardcoded — and a small primitive component library composes them into the higher-level UI.

## Tokens

### Colour
A single palette covers light and dark themes with a consistent semantic role per token: `surface`, `surfaceVariant`, `surfaceElevated`, `border`, `textPrimary`, `textSecondary`, `textTertiary`, `primary`, `primaryActive`, plus tinted variants for status (success, warning, error, indigo, violet, amber, blue). Colours are accessed as `RobodorPalette.X` (iOS) and `RobodorColors.X` (Android). `Color(.systemX)` and raw hex values are not allowed in feature code.

### Typography
Six display roles — `tKpi`, `tTitle`, `tCardTitle`, `tBody`, `tSmall`, `tMeta`, `tMono` — mapped to system fonts with deliberate tracking and weight per role. View modifiers (`.tTitleStyle()`, `.tMetaStyle()`, etc.) carry the colour role too so a body label has the right secondary text colour by default.

### Radii / shadow / spacing
Discrete scales (`sm / md / lg / xl / xxl / hero / card / inset / pillBig`) so cards, buttons, modals and pills nest visually without ad-hoc magic numbers.

## Primitive components

Reusable shells that accept tokens, used everywhere instead of one-off `RoundedRectangle`s:

- `RCard` — content surface with the standard border + radius + padding
- `RSection` — labelled section header + content slot
- `RPill` — rounded status badge with tint role (success, warning, error, primary, neutral)
- `RDot` — animated connection-state indicator (pulse / blink / steady)
- `RKpiCard` — KPI tile with label + big value + sparkline / icon slot
- `RGauge` — dial / arc gauge for live values
- `RSparkline` — minimalist trend line for KPI cards
- `RDoorViz` — bespoke door visualisation (panels lift / lower with the live position; idle states are a static frame so the canvas isn't redrawing 60 fps for nothing)
- `RDoorTriggerButton` — long-press control with haptic feedback and a clear active state
- `RTabBar` — bottom navigation with 44pt minimum touch targets
- `RStatusBadge` — small inline status chip

Same vocabulary on Compose (with `R*` Composable functions instead of structs).

## Localisation

All user-visible strings live in resource catalogues — `Localizable.strings` per `.lproj` on iOS, `strings.xml` per locale on Android — across **TR, EN, DE, FR, IT**. The default language is Turkish; English is the secondary canonical reference. Strings are accessed via a `preferencesStore.localized(key)` helper (iOS) / `stringResource(R.string.key)` (Android). A pre-commit lint check fails the build if a key exists in one locale but is missing in another.

## Accessibility

- Touch targets minimum 44pt (iOS) / 48dp (Android) on interactive surfaces.
- Custom `Canvas`-drawn views (door viz, gauges) expose `accessibilityLabel` and `accessibilityValue` so VoiceOver / TalkBack reads them as a single semantic element.
- Status colour is never the only signal — rolled up state has both colour and an icon (`checkmark.circle.fill`, `exclamationmark.triangle.fill`, etc.).
- Dynamic Type is respected for text-heavy screens; numeric KPIs use a `monospaced` font so they don't reflow when the value width changes.

## Idle-aware animation

`TimelineView(.animation)` and infinite Compose animations are gated on actual state. The door viz only ticks while `state == .opening || .closing`. Connection dots only pulse when actually connecting. The radar canvas on the scan screen freezes when no scan is in progress. The result is dramatically lower CPU and battery use compared to a naive "always animate" implementation, with no visible difference to the user.
