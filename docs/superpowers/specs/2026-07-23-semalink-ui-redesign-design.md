# SemaLink UI Redesign Design

## Goal

Align the existing HarmonyOS ArkTS UI with the supplied SemaLink reference image while preserving the current query, device discovery, progress, evidence, and history behavior.

## Scope

- Rework `Index`, `DeviceOverview`, `QueryHome`, and `QueryHistory` presentation.
- Replace the current top pill navigation with a fixed three-item bottom navigation for query, devices, and history.
- Use Chinese labels and the reference information hierarchy.
- Keep diagnostics available through existing internal code, but remove it from the primary navigation.
- Keep all existing `AppRuntime` actions and `AppSnapshot` fields as the source of truth.

## UI Structure

### Query page

The page uses a compact header with a menu affordance, centered SemaLink title, and notification affordance. It shows the online-device summary, a single-line query input with send action, query scope chips, a vertical progress timeline, and an answer summary with confidence and evidence/source affordances.

### Device page

The page shows a `2 / 3`-style online summary, the local device card, and remote device cards. Each card exposes online/offline state, connection state, knowledge type, index state, and recent synchronization information using data already present in `AppSnapshot` and `PeerStatusSnapshot`.

### History page

The page shows search and clear affordances, filter chips for all/success/insufficient evidence/no result/offline, and records grouped by date. Each record preserves selection behavior and displays question, time, result state, source, and confidence/evidence metadata where available.

### Shared visual language

- White page background with light gray borders and restrained shadows.
- Blue accent for active navigation, actions, and current progress.
- Green for successful/online states, orange for insufficient evidence, and gray for offline/no-result states.
- Small rounded cards with stable spacing and typography suitable for phone-width screens.
- Fixed bottom navigation with icon-like symbols and text labels.

## Data Flow and Compatibility

The existing subscription to `AppRuntime.current().store` remains unchanged. UI events continue to call the existing submit, cancel, retry, refresh, and record-selection callbacks. No changes are planned to query routing, transport, persistence, or collaboration models.

If a reference-only field such as a formatted time, confidence percentage, or device category is not present in the current model, the UI will use the closest existing field or a stable fallback label rather than changing the domain model in this pass.

## Verification

1. Run the existing ArkTS unit tests relevant to `Index`, automatic query UI, collaboration record state, and history behavior.
2. Run the module build/lint check.
3. Review the final diff to ensure unrelated user changes remain untouched and no business-layer files were modified unnecessarily.
