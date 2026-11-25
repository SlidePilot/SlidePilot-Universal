---
title: Pre-Rendering
nav_order: 9
parent: Features
---

# Pre-Rendering

This page explains how the pre-rendering mechanism works.

### Pre-Rendering

Pre-Rendering happens on different actions:

#### Opening a document

As soon as a new document is loaded in SlidePilot, a background task will start rendering the first 200 pages of the PDF.&#x20;

#### Changing the page

Everytime a new page is selected in SlidePilot (either through the key controls or the navigator), a new render task will be started in the background, which renders the surrounding 50 pages of the requested page. I.e. 100 pages will be rendered, if they are not already in the cache.

### Caching

Everytime a background render task finishes, the rendered page will be saved in the cache. So everytime the user requests a page, it will be first looked up in the cache, if this page is already rendered. If not (very unlikely because most pages a pre-rendered in the background) the page will be rendered directly and also saved in the cache.

The cache limit is set to 200 pages, which currently is set as-is and cannot be changed by the user, because there is no need to. This may be changed if there are requests for it. The cache limit ensures, that the users memory won't get exhausted.
