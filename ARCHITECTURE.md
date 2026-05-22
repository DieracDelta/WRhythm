# WRhythm Architecture Notes

WRhythm is a SwiftUI app family using an MVVM-style structure: views render observable state, shared managers coordinate playback, sync, downloads, and API calls, and platform-specific UI adapts around those shared services.

## Boundaries

- Shared playback, sync, download, and API behavior should stay UI-framework-light and reusable across iPhone, watchOS, and macOS.
- Platform-specific interaction surfaces belong behind small adapters or modifiers. `TrackActions.swift` owns row actions and chooses watch swipe actions versus iPhone/macOS context menus.
- Views should call intent-style helpers or manager methods, not duplicate action menus across screens.

## Warning Budget

Source warnings are treated as tech debt and should stay at zero. Xcode/tooling warnings that are outside app source, such as AppIntents metadata extraction noise or simulator asset trait messages, are allowed unless they begin masking real source warnings.

Run:

```sh
Scripts/check-source-warnings.sh
```

## Migration Direction

The project currently uses an Xcode synchronized root group under `WRhythm Watch App`, so some shared files physically live in a watch-named folder. New cross-platform code should be written with clear shared/platform boundaries first. A later mechanical move to folders such as `Shared/Services`, `Shared/Domain`, and `Platforms/Watch` should be kept separate from behavior changes.
