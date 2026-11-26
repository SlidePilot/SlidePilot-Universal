# 0021 – User documentation in this repository, published with GitHub Pages

- Status: Accepted
- Date: 2026-11-25

## Context
The user documentation lived on GitBook (`slidepilot.gitbook.io/slidepilot`). The project lost edit access to that GitBook space, so the pages can no longer be updated for 2.0, and the site may disappear without notice. The app's Help menu (SET-06), the README, the issue template and the App Store support URL link to it, and the parity workflow reads it as the reference for the old behavior.

A project website on its own domain (`slidepilotapp.com`) is planned for later, in a separate repository with GitHub Pages.

Options:
- **This repository, GitHub Pages, subdomain `docs.slidepilotapp.com`.** Docs change in the same PR as the feature. Adds one folder and one workflow.
- **Separate repository `SlidePilot/docs`.** Would be served at `slidepilot.github.io/docs` and, once the website repository has the apex domain, at `slidepilotapp.com/docs`. Keeps Pages out of the app repository, but every feature needs a second PR in another repository.
- **Another hosted service.** Repeats the lock-in that caused this problem.

GitHub Pages serves a project site at `<org>.github.io/<repository name>`, so a `/docs` path cannot come from this repository.

## Decision
- The user documentation lives in **`site/`** as Markdown and is published with **GitHub Pages** at **`docs.slidepilotapp.com`**. Until the domain is set up it is served at `slidepilot.github.io/SlidePilot-Universal`.
- The site is built with **Starlight** (Astro) in `.github/workflows/docs.yml` and deployed with GitHub's own Pages actions: pull requests that touch `site/` build it as a check, pushes to `main` deploy it. There is no `gh-pages` branch and no `CNAME` file; the custom domain is set in the repository's Pages settings.
- `site/` is a small Node project (`package.json`, `package-lock.json`, `astro.config.mjs`); the pages are in `site/src/content/docs/`, the images in `site/src/assets/`, and the sidebar order is set in `astro.config.mjs`. Starlight, Astro and their npm dependencies are part of the website only, not of the app; this ADR is their approval.
- `site/` starts from the old GitBook pages. Updating them for 2.0 is tracked in its own issue.
- A **frozen copy of the old GitBook pages** stays in `docs/legacy-user-docs/`. It is the reference for the old behavior (parity reviewer, `implement-issue` skill) and is never updated.
  - *Update:* the frozen copy was later removed from the repository. It stays available in git history at commit `34d7287`; the old code remains the reference for behavior.
- `docs/` stays internal developer documentation; nothing in it is published.
- Changes that only touch `site/` count as docs in CI and skip the macOS and iPad jobs.

## Theme (revised 2026-11-25)
The site first used Jekyll with the **Just the Docs** theme. It was replaced by **Starlight** before the 2.0 release:
- Starlight looks current, follows the system's light and dark mode, and has full-text search (Pagefind) and an accessible sidebar and table of contents built in.
- Just the Docs needed Ruby tooling only in CI, but its look is dated and its dark mode is a fixed scheme.
- Cost: Node tooling in `site/` (a lockfile and npm dependencies to update now and then). Building locally needs Node; otherwise the Docs workflow in the PR is the check.

## Consequences
- Docs and code can change in one PR; Claude updates the pages together with the feature.
- The documentation no longer depends on an account outside the GitHub organization.
- The maintainer sets up the DNS record (`CNAME docs` → `slidepilot.github.io`), turns on Pages with "GitHub Actions" as the source and enters the custom domain once. Verifying the domain for the organization protects the subdomain against takeover.
- The future website in its own repository can link to `docs.slidepilotapp.com`; both sites deploy independently.
- The public links (Help menu, README, issue template, App Store support URL) switch to the new site once it is live and up to date for 2.0.
