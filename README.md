# PokeAssist iOS prototype

PokeAssist is an iOS 27 technology prototype for testing full-display capture while Pokemon GO is frontmost. It uses ScreenCaptureKit to count captured frames, exposes the current count in a Live Activity / Dynamic Island, and performs an initial on-device Vision OCR pass for Pokemon detail and appraisal screens.

Version 0.4.0 recognizes appraisal/detail screen text and combat power (`CP`/`WP`). On an appraisal screen it also measures the three visible bars and reports experimental Attack/Defense/HP values plus the total IV percentage. An offline catalog now matches German and English species names, marks Legendary, Mythical, and Ultra Beast classes, records known Shiny availability, and warns when a species has known event/costume variants. Possible Shiny + event combinations are called out together. These catalog facts are protection hints, not proof that the individual on screen is Shiny or wearing a costume, so the app deliberately never marks a Pokémon as safe to transfer.

The analyzer converts ScreenCaptureKit's native iPhone pixel format to BGRA before measuring the bars. The first IV calibration is based on a confirmed `15/15/9` appraisal; more combinations still need device testing. It keeps the last meaningful Pokemon result visible after returning to PokeAssist and shows a short OCR diagnostic when no match is found. Both the host app and embedded widget extension explicitly declare Live Activity support. Before starting a new Live Activity, the app removes orphaned activities left by earlier builds and displays ActivityKit's actual state in the app. The build ad-hoc seals the nested extension and its host before packaging so a sideloading tool can replace intact signatures instead of producing an invalid extension page. The app intentionally does not use Pokemon GO account access, automation, network uploads, or an Android-style floating overlay.

## Requirements

- An iPhone running iOS 27 or later
- Xcode 27 to build locally, or the included GitHub Actions workflow
- A sideloading tool that signs the unsigned IPA with your Apple account before installation

The workflow artifact has no Apple development signature and cannot be installed or launched directly on a standard iPhone. Its code is ad-hoc sealed only to preserve a valid nested-code structure; a sideloading tool must replace those seals with signatures for the test device.

## Test flow

1. Build and install PokeAssist on the iPhone.
2. Open PokeAssist and tap **Start screen capture**.
3. Approve the full-display capture in Apple's system picker.
4. Confirm that the frame counter is increasing.
5. Switch to Pokemon GO.
6. Open a Pokemon detail or appraisal screen.
7. On the appraisal screen, keep all three bars visible for a few seconds.
8. Confirm that PokeAssist reports the local OCR result and experimental Attack/Defense/HP values.
9. Read the protection warning. A catalog match can identify a protected rarity class and possible Shiny/event variants, but the visible Shiny and costume state must still be checked in Pokémon GO.

If Live Activities are disabled, PokeAssist now shows that state inside the app instead of silently hiding the failure. Enable them in the iPhone settings for PokeAssist and retry.

## GitHub build

The workflow in `.github/workflows/build-unsigned-ipa.yml` runs automatically for pushes to `main` and can also be started manually. It builds both the app and Live Activity extension without an Apple identity, ad-hoc signs nested code from the inside out, verifies the signatures both before and after packaging, then uploads `PokeAssist-unsigned.ipa` as a workflow artifact for final device signing.

## Privacy

Screen capture starts only after explicit selection in Apple's system UI. Vision OCR runs on-device at a throttled interval. The prototype processes frames in memory only, does not save screenshots or video, and does not upload captured content.

## Offline catalog and safety limits

The bundled `pokemon_catalog.json` is a versioned build-time snapshot. Species names and Legendary/Mythical flags come from [PokéAPI](https://pokeapi.co/docs/v2), Shiny release hints come from [PoGo API](https://pogoapi.net/documentation/), and Pokémon GO costume-form hints come from [WatWowMap's generated GO data](https://github.com/WatWowMap/pogo-data-api). The source snapshot can be regenerated with `tools/generate-pokemon-catalog.ps1`; the app does not contact these services at runtime.

Spawn rarity, event availability, and collector value change with time, region, and events. Therefore `Standard` means only “not classified as Legendary, Mythical, or Ultra Beast”; it does not mean common or disposable. A Shiny release hint does not prove that the captured Pokémon is Shiny, and a costume-capable species does not prove that the captured individual is an event form. Until visual detectors are calibrated with real-device examples, PokeAssist always requires a manual check before transfer.
