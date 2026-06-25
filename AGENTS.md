# Agent Guide For Rocio

Rocio is moving from a PWA MVP toward an App Store-ready iOS app. Agents working in this repo should optimize for launch quality, privacy, and small reviewable PRs.

## Current Stack

- PWA MVP: `index.html`, `manifest.webmanifest`, `sw.js`.
- Local assets: `assets/flowers/`.
- Plant.id proxy: `supabase/functions/identify-flower/index.ts`.
- QA harnesses: `qa/`.
- Project brain: `GBRAIN.md`.
- Launch plan: `APP_STORE_LAUNCH_PLAN.md`.

## Required Local Checks

Run the strict classifier harness when touching scanner, catalog, image assets, or flower matching logic:

```sh
node qa/readonly-flower-classifier-harness.mjs --strict
```

If a local browser smoke is needed, serve the app from the repo root:

```sh
python3 -m http.server 8000
```

Then inspect `http://localhost:8000/` on mobile-sized and desktop-sized viewports.

## Review Priorities

Lead reviews with issues, not praise. Block or request changes for:

- secrets committed to browser/client code;
- Plant.id or scanner claims that overstate certainty;
- camera/photo usage without privacy copy;
- notification flows that request permission before user intent;
- App Store work that is only a thin WebView wrapper;
- changes that break offline/local MVP behavior;
- unlicensed or unattributed image assets;
- missing tests for classifier, persistence, or native routing changes.

## App Store Standards

Every App Store-facing PR should answer:

- What native value does this add beyond the PWA?
- What privacy/data collection impact does it introduce?
- How is the user told about camera, photos, notifications, or provider calls?
- What happens offline or when Supabase/Plant.id is unavailable?
- What check proves the change works?

## App Intents Standards

Keep the first intent surface small:

- Open garden.
- Log watering for a saved plant.
- Open scanner.

Use a central handoff route. Do not add one intent per tab unless there is a clear system-surface use case.

## Branch And PR Rules

- Prefer branch names starting with `fsociaty/`.
- Keep PRs small and reviewable.
- Update `GBRAIN.md` or `APP_STORE_LAUNCH_PLAN.md` when a decision changes.
- Include test notes in every PR.
- Do not approve a PR if launch/privacy risk is unresolved.