# Copilot instructions for dBMeter

This is a lightweight macOS menu bar decibel meter built in SwiftUI with AppKit support. Use these instructions to keep suggestions aligned with the app's current architecture and design.

## Project overview

- A macOS menu bar app with a popover UI and status bar display.
- `AudioMeter` is the core observable model that manages AVAudioEngine, microphone access, input selection, smoothing, weighting, and threshold alerts
- `ContentView` is the SwiftUI view bound to `AudioMeter` and exposes settings, controls, and readouts
- `AppDelegate` creates the status item, updates its title/appearance, and manages the popover

## General guidelines

- Prioritize simple, readable code
- Do not introduce unnecessary dependencies or complex UI frameworks; use native elements whenever possible


## Style and conventions

- Keep code idiomatic Swift and follow SwiftUI patterns
- Preserve separation between UI and audio logic
- Avoid putting business logic directly in `ContentView`; `AudioMeter` should own meter state and audio engine details
- Use `@MainActor` where UI-facing state is updated or when working with AppKit/SwiftUI interactions
- Prefer small, focused changes over broad refactors unless the user explicitly asks for architecture changes


## When editing or extending

- Keep the menu bar text and popover UI in sync through `AudioMeter` published properties
- Prefer `Binding` wrappers and computed properties for UI bindings, as already used in `ContentView`
- Keep the popover view simple and focused on meter controls, thresholds, and metering settings


## Testing and quality

- If adding behavior, also add or update unit tests in `dBMeterTests`.
- Keep code readable and maintain numeric formatting consistent with existing `formatDecibels(...)` usage.
- Maintain the current macOS-specific UX: status item control, right-click popover open, left-click start/stop toggle.


## Helpful reminders for Copilot

- This is a macOS app, not an iOS app
- The app is built with SwiftUI and native AppKit status bar integration
- The app should remain lightweight and focused on accurate audio metering
- Use `AudioMeter.FrequencyWeighting` and `AudioMeter.IntegrationPreset` enums for UI controls and metering settings

If asked to add a feature, fix a bug, or refactor code, keep changes consistent with this existing architecture and the small macOS utility nature of the app.