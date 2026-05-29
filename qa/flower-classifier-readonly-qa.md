# Rocio Local Flower Classifier Read-Only QA

Scope: test the browser-local flower classifier in `index.html` without changing app files. The harness reads the current classifier block, provides a synthetic canvas, and checks whether flower-like color distributions are routed to the expected local catalog flower.

## Commands

Run the exploratory harness:

```sh
node qa/readonly-flower-classifier-harness.mjs
```

Run it as a failing gate after a classifier fix:

```sh
node qa/readonly-flower-classifier-harness.mjs --strict
```

## What This Proves

- It directly exercises the same `identifyPlant`, `sampleImageColors`, `rgbToHsl`, and `scoreFlowerMatch` logic used by the app.
- It does not depend on Plant.id, Supabase, camera permissions, service workers, or browser cache state.
- It creates deterministic synthetic canvas/image distributions for lily-like, gardenia-like, jasmine-like, daisy-like, marigold-like, tulip-like, sunflower-like, hydrangea-like, violet-like, geranium-like, and ambiguous non-lily cases.
- It specifically counts non-lily scenarios that classify as `lirio`.

## Current Risk Hypothesis

The local matcher is color-only and the `lirio` profile accepts:

- orange hues: `20-45`
- green hues: `80-160`
- medium-to-high lightness: `0.5-0.9`
- white bonus weight

That overlaps with gardenia, jasmine, margarita, cempasuchil, tulipan, and generic pale flower/leaf images. Any fix should reduce `lirio` false positives without breaking a clear lily-like control case.

## Current Results

Last command run:

```sh
node qa/readonly-flower-classifier-harness.mjs --strict
```

Exit code: `0` after the no-lirio-bias fix.

Summary:

- `total`: 12 named scenarios
- `passed`: 12
- `failed`: 0
- `nonLilyClassifiedAsLirio`: 0
- palette sweep non-lily distributions classified as `lirio`: 0

Important observed failures:

- The original failing cases are now covered by the strict harness.
- The browser regression also checks all 15 catalog images and a leaf/wood background case that must not surface `lirio` as the result.
- The local matcher remains a rough fallback, not a substitute for Plant.id/Supabase vision recognition.

## Suggested Post-Fix Acceptance Criteria

- `node qa/readonly-flower-classifier-harness.mjs --strict` exits `0`.
- `nonLilyClassifiedAsLirio` is `0`.
- `nonLilyPaletteSweepClassifiedAsLirio` is `0`.
- The lily positive control still returns `lirio`.
- Gardenia-like white/dark-green returns `gardenia`, not `lirio`.
- Jasmine-like white/light-green returns `jazmin`, not `lirio`.
- Daisy-like white/yellow returns `margarita`, not `lirio`.
- Marigold-like orange/yellow returns `cempasuchil`, not `lirio`.
- Ambiguous white/green/orange and pale-green/white cases are either not `lirio` or are explicitly marked uncertain with `lirio` absent from the first result.
- Any real-browser scanner smoke after the fix should show top candidates and uncertainty text for low-separation cases, not a confident single `Lirio`.

## Fix Direction To Prove Later

The harness should fail before the fix if `lirio` is over-broad, then pass after one of these changes:

- make `lirio` require a stronger orange-plus-white relationship than gardenia/jasmine;
- penalize `lirio` when green dominates and orange is absent or weak;
- add a minimum score separation for `lirio` before it can be the top non-uncertain result;
- use shape/region hints for lilies if the app stays local-only, instead of relying only on color bins.
