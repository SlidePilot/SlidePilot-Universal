# 0005 – Leaner pre-rendering cache

- Status: Accepted (final scope after Phase 1 measurement)
- Date: 2026-11-10

## Context
The old app rendered pages 0…200 on open and ±50 pages around each requested page into an `NSCache` with a count limit of 200. The rendering was in fact lazy, and it mutated shared PDF pages across threads (parity doc DEF-02).

## Decision
- Keep a render cache, implemented as an actor.
- Priority: current page and next page first, then the neighborhood in the background.
- The limit is memory-based (bytes), not a page count. iPad gets a smaller budget.
- The exact neighborhood size and budget are set after measurement in Phase 1 with large Beamer decks.

## Consequences
- Phase 1 includes a measurement prototype (render time per page, memory per image, at presenter and full-screen sizes).
- Parity item PRE-01 is `changed`.
