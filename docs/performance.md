# Performance check for 2.0

Release check of issue #41: does SlidePilot stay fast and within its memory budget with a large deck and a long presentation? The render cache parameters themselves come from the Phase 1 measurement ([`prototypes/render-cache.md`](prototypes/render-cache.md), ADR 0005).

## What was checked

- **Large deck:** `Fixtures/large-deck.pdf` (320 pages), presented at a 4K audience size (2880×2160 per page, 23.7 MiB per image) with the iPad budget (192 MiB), which is the tighter of the two. The test `LongPresentationTests` in `SlidePilotRenderingTests`:
  - steps forward through all 320 pages and back again (646 steps), waiting for each current page like the presenter does;
  - then jumps like the overview or Go to Page would (no neighborhood rendered yet);
  - then requests every thumbnail like a sidebar scrolled from top to bottom;
  - checks after every step that the cache stays within its slide and thumbnail budgets.
- **Long presentation:** `PresentationTimerTests.longPresentationWithBreaksStaysExact` runs eight 90-minute blocks with breaks (12 hours) and a 45-minute timer 10 hours into overtime. The times come from start instants, not from counted ticks (TIME-07), so they stay exact.
- **In the app:** `large-deck.pdf` opened in the iPhone simulator (iPhone 18 Pro Max); paging with the arrow keys, scrolling the slide list quickly and jumping to a page from it showed no visible delay and no blank slides.

## Results

| | Mac | iPad simulator |
|---|---|---|
| Step median | 2.1 ms | 2.6 ms |
| Step p95 | 3.1 ms | 9.5 ms |
| Slowest step | 21 ms | 52 ms |
| Peak slide cache | 189 MiB of 192 MiB | 189 MiB of 192 MiB |

Apple-silicon Mac, macOS 27, Xcode 27.2, Debug build; iPad simulator "iPad Pro 13-inch (M5)" on the same Mac. Single runs.

- The cache never exceeds its budget; it fills it and then evicts the least recently used pages outside the neighborhood, as designed.
- The step time does not grow over the run: the last steps are as fast as the first ones.
- The timer shows the exact time after 12 hours with breaks and 10 hours of overtime.

## Limits

- The fixture pages are simple text pages. Image- and TikZ-heavy pages take 0.3–0.8 s each at 4K to 6K (see the Phase 1 measurement); the neighborhood pre-render hides this for normal forward navigation, jumps render on demand.
- The simulator has no per-app memory limit and runs on the Mac's CPU and GPU. Memory and speed on a real iPad or iPhone (especially older models) and a presentation of several hours on real hardware with an external display are part of the TestFlight check before release (see [`release.md`](release.md)).

## Re-running

```sh
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -destination 'platform=macOS' -only-testing:SlidePilotRenderingTests/LongPresentationTests test
```

The numbers are in the log line starting with `LONGPRESENTATION`. Use an iPad simulator or a connected device as the destination for iPadOS numbers.
