# PokeAssist iOS prototype

PokeAssist is an iOS 27 technology prototype for testing full-display capture while Pokemon GO is frontmost. It uses ScreenCaptureKit to count captured frames, exposes the current count in a Live Activity / Dynamic Island, and performs an initial on-device Vision OCR pass for Pokemon detail and appraisal screens.

Version 0.2.1 recognizes appraisal/detail screen text and combat power (`CP`/`WP`) as the first step toward IV calculation. It keeps the last meaningful Pokemon result visible after returning to PokeAssist and shows a short OCR diagnostic when no match is found. Exact IV-bar measurement is not implemented yet. The app intentionally does not use Pokemon GO account access, automation, network uploads, or an Android-style floating overlay.

## Requirements

- An iPhone running iOS 27 or later
- Xcode 27 to build locally, or the included GitHub Actions workflow
- A sideloading tool that signs the unsigned IPA with your Apple account before installation

An unsigned IPA cannot be installed or launched directly on a standard iPhone. The workflow artifact is deliberately unsigned so it can be signed for the test device afterward.

## Test flow

1. Build and install PokeAssist on the iPhone.
2. Open PokeAssist and tap **Start screen capture**.
3. Approve the full-display capture in Apple's system picker.
4. Confirm that the frame counter is increasing.
5. Switch to Pokemon GO.
6. Open a Pokemon detail or appraisal screen.
7. Confirm that the PokeAssist Live Activity / Dynamic Island continues to update and shows the local OCR result.

If Live Activities are disabled, PokeAssist now shows that state inside the app instead of silently hiding the failure. Enable them in the iPhone settings for PokeAssist and retry.

## GitHub build

The workflow in `.github/workflows/build-unsigned-ipa.yml` runs automatically for pushes to `main` and can also be started manually. It builds both the app and Live Activity extension with code signing disabled, packages `PokeAssist.app` as `PokeAssist-unsigned.ipa`, and uploads the IPA as a workflow artifact.

## Privacy

Screen capture starts only after explicit selection in Apple's system UI. Vision OCR runs on-device at a throttled interval. The prototype processes frames in memory only, does not save screenshots or video, and does not upload captured content.
