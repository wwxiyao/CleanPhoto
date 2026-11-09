# CleanPhoto

<img src="docs/brand/cleanphoto-logo-original.png" width="128" alt="CleanPhoto icon">

A photo-cleanup app for iPhone and iPad, built with SwiftUI. Review a random batch of ten photos with two simple gestures, group near-duplicates with Apple's Vision framework, and confirm deletions only after a review pass. Everything runs on-device: no accounts, no servers, no uploads.

## Why

Most photo cleaners want an account, a subscription, or your library on their server. CleanPhoto is deliberately small:

- **Batch, not infinite scroll.** Ten photos at a time, picked at random, shown in library order. Finish a batch, review what you marked, then move on.
- **Two gestures.** Swipe up to queue a photo for deletion, swipe left to keep it. Nothing is removed until you confirm.
- **Similar shots, grouped locally.** Feature prints are computed with `Vision` on the device and cached, so near-duplicates can be reviewed side by side.
- **No network code at all.** The app has no HTTP client, no analytics SDK, and no third-party dependencies.

## Features

- Random batches of 10 photos; processed photos never reappear
- Swipe up to mark for deletion, swipe left to keep
- Review sheet after every batch: recover mis-taps, delete, or skip
- Similar-photo groups with cached on-device feature prints
- Favorites and per-device cleanup progress
- Works with limited photo-library access
- iPhone, iPad, and Mac Catalyst targets
- Chinese UI for now — localization contributions are welcome

## Privacy

| | |
|---|---|
| Network access | None. The app contains no networking code and no third-party SDKs. |
| Photo processing | On-device only, via Apple's `Vision` framework. Photos are never uploaded. |
| Accounts | None. There is no login, sync, or cloud storage. |
| Deletion | Always explicit: you review the batch and confirm before anything is deleted. |
| Permissions | Photo-library read access only, plus App Sandbox on Mac. |
| Data | Batch state and the similarity cache are stored locally per device. |

## Requirements

- iOS 26.0 or later (iPhone / iPad); a Mac Catalyst build is included
- Xcode 27 or later
- No package dependencies

## Build and run

```sh
git clone https://github.com/wwxiyao/CleanPhoto.git
cd CleanPhoto
open CleanPhoto.xcodeproj
```

Select the **CleanPhoto** scheme and an iPhone simulator, then run. For a physical device, pick your development team under *Signing & Capabilities*.

Command-line build:

```sh
xcodebuild -project CleanPhoto.xcodeproj -scheme CleanPhoto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Tests

The core logic (batching, sorting, metadata, similarity queue, session state) is packaged as a small SwiftPM library, so it can be tested on macOS without a photo library:

```sh
swift test
```

Twelve test files cover batch selection, favorites, metadata parsing, viewer state, and similarity grouping.

## How it works

| Piece | Responsibility |
|---|---|
| `BatchManager` | Picks random batches, tracks the current index, records keep/delete decisions |
| `PhotoLibraryService` | Thin wrapper over `PHPhotoLibrary` / `PHAsset` |
| `SimilarityService` | Runs `VNGenerateImageFeaturePrintRequest`, clusters by feature-print distance |
| `SimilarityCacheManager` | Persists feature prints so rescans are cheap |
| `LibraryViewModel` | Drives loading, permission state, deletion, and navigation |
| `SwipeContainerView` | Gesture handling and card presentation |
| `ReviewSessionStore` | Keeps cleanup progress per device |

## Project layout

```
CleanPhoto/          App sources (SwiftUI views, services, models)
  Services/          Vision similarity, cache, ignored groups
  Views/             Photo detail and supporting views
Tests/               SwiftPM tests for platform-independent logic
docs/                Design notes, product brief, review reports
```

## Status

`v1.0.0` is usable day to day. Known limitations:

- Deletion still goes through the system confirmation sheet.
- The first similar-photo scan of a large library is CPU-intensive; results are cached afterwards.
- The interface is Chinese-only at the moment.

## License

MIT — see [LICENSE](LICENSE).
