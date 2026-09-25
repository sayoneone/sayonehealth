# Design rubric (LLM-as-judge)

Rubric used to score competing architecture proposals for SayoneHealth
(iOS + watchOS fluid-intake tracker). Built with the `llm-judge` methodology:
pointwise scoring (no pairwise → no position bias), proposals anonymised as
P1..P3, one judge lens per group of criteria, rationale written before the
score, every score must cite evidence from the proposal.

## System under test

- **Name**: architecture proposal for SayoneHealth v1
- **Input type**: product requirements + verified platform facts (research digest)
- **Output type**: architecture document (targets, data flow, HealthKit/Widget/Siri strategy, file tree)
- **Deployment context**: personal app, tested next morning on a real iPhone + Apple Watch
  and in the simulator; no Mac available during development — CI is the only compiler.

## Criteria

### C1. Requirements coverage — trajectory, 3-point (lens: product)
- **Definition**: every explicit user requirement is addressed with a concrete mechanism.
  Requirements: log drinks by tapping; choose drink type (water, Coke Zero, others,
  custom); every entry lands in Apple Health; Apple Watch app; tidy watch widget /
  complication; widget configurable so one tap logs a preset (e.g. 500 ml water);
  Siri integration.
- `pass`: all requirements mapped to a concrete component and flow.
- `partial`: exactly one requirement vague or hand-waved (e.g. "Siri via App Intents" with no intents listed).
- `fail`: any requirement missing, or two or more vague.
- **Failure modes caught**: silently dropping Siri on watch, widget not configurable, cola logged nowhere in Health.

### C2. Build safety — trajectory, 3-point, weight ×3 (lens: platform/API)
- **Definition**: the design compiles on the first CI runs without a local Mac.
  Uses only APIs available at the declared deployment targets (with `#available`
  / `#if compiler` guards for newer ones), avoids unverified APIs, avoids
  capabilities unavailable to a free Personal Team (iCloud, Push, SiriKit
  entitlement), project generated reproducibly (XcodeGen), Swift 5 language mode.
- `pass`: every framework API named is verified in the research digest or guarded; no paid-only capability required.
- `partial`: one unguarded newer API or one unverified API on a non-critical path.
- `fail`: core flow depends on an unverified/unavailable API, or needs a paid-only capability.
- **Failure modes caught**: ControlWidget used on watchOS 11, SiriKit Intents extension, Swift 6 strict-concurrency errors.

### C3. Data correctness & sync — trajectory, 3-point, weight ×2 (lens: data)
- **Definition**: HealthKit writes are idempotent (sync identifiers), no double counting
  between watch and phone, undo/delete removes the Health samples, writes made while the
  device is locked or from an extension are not lost, widget/phone/watch totals converge.
- `pass`: all five properties addressed with a concrete mechanism.
- `partial`: one property missing.
- `fail`: two or more missing, or a design that double-counts by construction.

### C4. One-tap UX & platform fit — trajectory, 3-point, weight ×2 (lens: product)
- **Definition**: minimal taps from watch face / home screen / Control Center to a
  logged drink, with visible confirmation and undo; presets configurable per widget
  instance; sensible watch UI (Digital Crown for custom volume).
- `pass`: one tap from at least watch face + iPhone widget, confirmation + undo, per-instance config.
- `partial`: one-tap on one surface only, or no undo.
- `fail`: logging requires navigating the app.

### C5. Siri / App Intents quality — trajectory, 3-point, weight ×1.5 (lens: platform/API)
- **Definition**: App Shortcuts with natural Russian + English phrases, parameterised
  by preset/drink, runs without opening the app, available on watch, query intent for
  today's total, no SiriKit entitlement needed.
- `pass`: all of the above.
- `partial`: one missing.
- `fail`: two or more missing or relies on SiriKit Intents extension.

### C6. Simplicity & parallelisability — trajectory, 3-point, weight ×1.5 (lens: data)
- **Definition**: minimal moving parts; module boundaries and shared contracts clear
  enough that 4–6 engineers can implement modules in parallel without conflicts.
- `pass`: explicit module boundaries + shared type contracts.
- `partial`: boundaries clear but contracts implicit.
- `fail`: tangled; shared state everywhere.

### C7. Privacy & safety — trajectory, binary gate (lens: data)
- **Definition**: health data stays on device / Apple services, usage strings present,
  no medical claims, requests only the HealthKit types it uses.
- `pass` / `fail`. Fail is sticky: a failing proposal cannot win.

## Aggregation

Weighted: pass = 2, partial = 1, fail = 0; weights C1 ×3, C2 ×3, C3 ×2, C4 ×2,
C5 ×1.5, C6 ×1.5; C7 is a gate. Winner is the highest weighted score; the synthesiser
grafts the best ideas from runners-up and must fix every `must_fix` any judge raised.

## Bias controls

- Pointwise, one proposal per judge call → no position bias.
- Proposals anonymised, angle names stripped → no self-preference / framing.
- "Do not reward length or polish" instruction → verbosity & halo bias.
- Rationale before score + mandatory evidence quotes → ordering effect.
- `partial` only allowed with the specific anchor condition → middle-score cop-out.
