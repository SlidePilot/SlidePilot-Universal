# 0005 – Leaner pre-rendering cache

- Status: Accepted (parameters set after the Phase 1 measurement)
- Date: 2026-11-10

## Context
The old app rendered pages 0…200 on open and ±50 pages around each requested page into an `NSCache` with a count limit of 200. The rendering was in fact lazy, and it mutated shared PDF pages across threads (parity doc DEF-02).

## Decision
- Keep a render cache, implemented as an actor.
- Priority: current page and next page first, then the neighborhood in the background.
- The limit is memory-based (bytes), not a page count. iPad gets a smaller budget.
- Parameters, set after the Phase 1 measurement (`docs/prototypes/render-cache.md`, issue #8):
  - Neighborhood: current page −1 … +3. Render order: current, next, previous, then further ahead. Navigation cancels queued jobs that are no longer near the current page.
  - Budget, counted by the cache itself as `bytesPerRow × height` (Core Graphics image memory does not show up in the process footprint): **512 MiB on macOS, 192 MiB on iPadOS**. On a memory warning the iPad cache shrinks to the neighborhood.
  - Eviction: least recently used outside the neighborhood first; the current and next page are never evicted.
  - One rendition per page, display mode and size class; smaller views scale it down instead of rendering again. Thumbnails use their own small cache and render lazily.
  - No pre-rendering of the document on open; start with the neighborhood of the opened page.
  - One renderer for current/next and up to two background workers, each with its own `PDFDocument` kept open for the session. Every render runs inside `autoreleasepool`.
- The iPad budget is re-checked with real-device measurements before release (see the findings doc).

## Consequences
- Phase 1 includes a measurement prototype (render time per page, memory per image, at presenter and full-screen sizes).
- Parity item PRE-01 is `changed`.
