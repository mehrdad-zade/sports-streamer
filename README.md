# SportsStreamer

An iOS app that lists live sports events from a streaming index site, finds which of an event's stream sources are actually live, and plays the best one in the native video player — switching to another source automatically when the current one dies.

## Features

- **Event list** scraped from a configurable site (default `https://footy4u.st/`), with live badges, categories and team search.
- **Live source detection** — each source's embed page is loaded in a hidden web view and watched for an HLS (`.m3u8`) manifest request. Sources found this way play natively in `AVPlayer`.
- **Automatic failover** — sources are re-checked on an interval while you watch; if the playing stream errors, ends or stalls for 20 seconds, the app switches to the next live source.
- **Web player fallback** — when no direct stream can be extracted, the source page is shown in an ad-blocked web view (pop-ups, redirects and common ad networks are blocked).
- **Orientation-driven full screen** — rotating to landscape enters full screen, rotating back to portrait exits it. Picture-in-Picture is supported.

## Requirements

- Xcode 15 or later
- iOS 17.0 or later

## Getting started

1. Open `SportsStreamer.xcodeproj` in Xcode.
2. Select the `SportsStreamer` scheme and a simulator or device.
3. To run on a device, set your own team under *Signing & Capabilities*.
4. Build and run (⌘R).

From the command line:

```sh
xcodebuild -project SportsStreamer.xcodeproj -scheme SportsStreamer \
  -destination 'generic/platform=iOS Simulator' build
```

## Settings

Open the gear button in the bottom bar:

| Setting | Default | Description |
| --- | --- | --- |
| Site URL | `https://footy4u.st/` | The index site to scrape events from. |
| Re-check interval | 60 s (minimum 15 s) | How often sources are re-checked while watching. |
| Auto-switch | On | Jump to another live source when the current one fails. |

## Project layout

```
SportsStreamer/
  Models/       Event and StreamSource
  Scraping/     HTML fetching and heuristic parsing of event lists and source links
  Extraction/   StreamSniffer (finds HLS manifests), SourceMonitor (re-check loop), AdBlocker
  Playback/     WatchSession (failover logic), PlayerController (AVPlayer), native and web player views
  Store/        EventStore
  Settings/     AppSettings (persisted in UserDefaults)
  Views/        Root, event list, watch and settings screens
Tools/
  ParserCheck/  Command-line smoke test for the HTML parsers
```

## Parser smoke test

Check the scrapers against saved HTML pages on macOS, without running the app:

```sh
swiftc -o /tmp/pc Tools/ParserCheck/main.swift \
  SportsStreamer/Scraping/{HTML,EventListParser,SourceParser}.swift SportsStreamer/Models/*.swift
/tmp/pc home.html https://site/ event.html https://site/events/x
```

It prints the parsed events, categories and stream sources.

## Notes

- Automatic full screen on rotation uses a non-public `AVPlayerViewController` method, so this build isn't suitable for App Store submission. If the method is ever unavailable, rotation falls back to the inline landscape layout.
- The app doesn't host or provide any content; it only reads pages from the site you configure. Make sure your use complies with the laws and terms that apply to you.
