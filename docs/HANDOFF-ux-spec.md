# Hand-off: Lexicon UI/UX Specification

**Purpose.** This document hands off the design of Lexicon's suggestion UI to a
designer/agent. It (a) snapshots what already exists in code so the spec extends
reality instead of inventing in a vacuum, (b) states the hard constraints the
design must respect, and (c) supplies the **filled-in, ready-to-run prompt** for
the UI/UX spec task (the two `{{…}}` placeholders are resolved at the bottom).

Read alongside: [`../README.md`](../README.md), [`../BACKLOG.md`](../BACKLOG.md).

---

## 1. Project snapshot (what Lexicon is, today)

Lexicon is a **system-wide macOS writing companion** (SwiftPM, Swift 5.9, macOS 14+,
menu-bar accessory app). It captures the user's writing in the focused text element
of *any* app via the Accessibility API, infers their communicative **goal**, and
proposes higher-precision wording. It is **built and verified end-to-end** (capture →
Claude cascade analysis → suggestions UI → Tab-to-insert), and stably code-signed so
TCC grants survive rebuilds.

Pipeline: `CaptureEngine` (AXObserver, 350 ms debounce, default-deny allowlist,
secure-field exclusion) → `AnalysisRouter` (model cascade) → `OverlayController`
(ghost text + suggestions panel) → `EventTapController` (Tab interception) →
`Inserter` (span replacement / smart-spaced insert / clipboard-preserving paste).

Runtime model cascade (in `AppConfig.swift`): **Haiku** `claude-haiku-4-5-20251001`
on every tick (~2.0–2.5 s round-trip), escalating to **Sonnet** `claude-sonnet-4-6`
on low confidence / long input, **Opus** `claude-opus-4-8` for on-demand deep rewrite.

---

## 2. Current UI — ground truth (this is what the spec must evolve)

The shipping UI is deliberately minimal AppKit. The design spec replaces/elevates it.

### Ghost text (`GhostTextWindow` in `Sources/Lexicon/OverlayController.swift`)
- Borderless `NSWindow`, `backgroundColor = .clear`, `hasShadow = false`,
  `level = .floating`, `ignoresMouseEvents = true`, never key/main.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.
- One `NSTextField`, system font **13 pt**, `tertiaryLabelColor`.
- Positioned at the caret: `x = caretRect.maxX + 2`, `y = caretRect.minY`
  (caret rect from `kAXBoundsForRangeParameterizedAttribute`, converted to Cocoa
  bottom-left in `CaretLocator.swift`).
- **Shown/hidden with `orderFrontRegardless()` / `orderOut(nil)` — NO opacity
  animation today.** Implementing the "thought arising/dissolving" fade is the
  spec's headline requirement.

### Suggestions panel (`SuggestionsPanel`, same file)
- `NSPanel`, styleMask `[.nonactivatingPanel, .titled, .closable, .utilityWindow]`,
  `isFloatingPanel = true`, `level = .floating`, `canBecomeKey = false` (host app
  keeps keyboard focus — load-bearing for insertion).
- Header: bold **13 pt**, `"🎯 <goalLabel>  ·  <confidence%>"`.
- Rows: wrapping `NSButton`s — replacement bold 13 pt, rationale **11 pt**
  `secondaryLabelColor`; armed row gets `bezelColor = controlAccentColor`.
- Fixed row width **300 pt**; panel sized to fit; positioned just above the caret
  (`y = caretRect.maxY + 8`), flipping below if it would clip the screen top.
- **No fade, no per-category styling, no grouping** today.

### What does NOT exist yet (the spec defines all of this)
- Opacity/easing transitions of any kind (the meditative "thoughts" behavior).
- Distinct visual treatment for **vocabulary vs syntax vs cadence/flow**.
- Prioritization/grouping when many suggestions co-exist.
- Cadence/flow *commentary* (non-insertable observations) as a first-class type.
- Reduced-motion alternative, VoiceOver semantics for the floating panels.

---

## 3. Data contract the UI consumes

`AnalysisResult` (in `Sources/Lexicon/AnalysisResult.swift`), per analysis tick:
```
goalId: String          // kebab slug, e.g. "professional-clarity"
goalLabel: String       // human-readable goal
confidence: Double       // 0…1
suggestions: [Suggestion] // ranked best-first, ≤6
```
`Suggestion`: `original: String?` (span to replace, empty/nil ⇒ additive),
`replacement: String`, `rationale: String` (one line).

> **Schema gap the spec must flag for implementation:** the design requires three
> *kinds* — **vocabulary**, **syntax**, **cadence/flow** — and cadence/flow may be
> *commentary* (no `replacement` to insert). The spec should assume a `kind` field
> is added to `Suggestion` (`vocabulary | syntax | cadence`) and that cadence items
> can be advisory-only. Note this as a required model + prompt change, not a UI-only
> change.

---

## 4. Hard constraints the design MUST respect

1. **System-wide, caret-anchored.** The widget floats over arbitrary apps; it is not
   a WidgetKit widget (those can't take live input). Anchor to the AX caret rect;
   degrade gracefully when an app exposes no caret bounds (no anchor → fall back to a
   fixed screen corner, documented).
2. **Never steal focus.** Ghost = click-through, non-key. Panel = non-activating,
   `canBecomeKey = false`. The host app must keep first responder or Tab-insert breaks.
3. **Latency is real.** First suggestions arrive ~2–2.5 s after a typing pause (Haiku).
   The fade-in/timing must feel intentional given this, not like lag — design the
   appearance around the debounce (350 ms) + model latency, not instant.
4. **Tab is the accept gesture** (intercepted only when armed; Esc / any other key
   dismisses the ghost). Don't design an accept model that fights this.
5. **Privacy-first.** Default-deny allowlist, secure fields never read, minimal text
   over TLS, no persistence beyond session. The UI should make capture state legible
   (an unobtrusive "active/paused" affordance) without nagging.
6. **Accessibility + reduced motion.** Honor `NSWorkspace.accessibilityDisplayShouldReduceMotion`
   / reduce-transparency; provide a non-animated, screen-reader-navigable path.
7. **macOS-native feel.** AppKit `NSPanel`/`NSWindow` + Core Animation layer opacity
   (`CABasicAnimation` / implicit `animator()`), `NSVisualEffectView` materials,
   HIG-conformant type and spacing. SwiftUI hosted in an `NSHostingView` is acceptable
   for panel content if it keeps the non-key/non-activating behavior.

---

## 5. Deliverable expected from the spec task

A complete UI/UX specification with the **exact seven sections** named in the prompt,
precise enough to mock up and implement: measurements in pt/px, timing in ms,
named easing curves / cubic-bezier values, and the thought-like opacity behavior
specified implementably (fade-in delay/duration/curve, dwell, fade-out trigger/curve,
hover/focus overrides). Maintain the poetic, "thoughts arising and dissolving" tone
while staying buildable.

**Open questions to resolve in the spec (or flag as assumptions):**
- Does the panel persist while the ghost fades, or do both breathe together?
- Multiple simultaneous suggestions: one ghost at the caret + a panel list, or
  staggered inline ghosts? How many at once before it overwhelms?
- Cadence/flow commentary placement (it has no insertion point) — margin note? toast?
- How "active capture" is signaled per the privacy constraint.

---

## 6. Filled template inputs

### `{{WRITING_CONTEXT}}`
> The user is a writer/knowledge-worker composing prose in real time inside ordinary
> macOS apps — TextEdit, Mail, Notes, chat fields, web text areas — wherever they
> type. The writing is intent-driven: emails, reports, messages, notes, drafts, where
> the writer knows roughly what they mean but wants to say it with more precision,
> better grammar, and better rhythm. Lexicon watches the focused field system-wide
> (with the user's per-app consent), infers the writer's communicative *goal* (e.g.
> "persuade a stakeholder", "professional clarity", "emphatic achievement"), and
> surfaces suggestions that help them better *expound and elucidate that intent* —
> not generic grammar nags, but wording that lands the point. It must feel like a
> calm collaborator at the edge of awareness, not a popup that interrupts the act of
> writing. Suggestions are accepted inline with the Tab key; the experience should be
> meditative and almost subliminal, befitting the flow state of composing.

### `{{DESIGN_REQUIREMENTS}}`
> - Real-time analysis of the user's writing as they type (debounced ~350 ms; first
>   results ~2–2.5 s later via the on-device→API cascade).
> - Three suggestion kinds, visually distinguished: **vocabulary expansion**,
>   **syntax improvement**, **cadence/flow** (the last may be advisory commentary
>   with no inline insertion).
> - Every suggestion ties back to the inferred goal (show goal + confidence) and is
>   framed as helping the writer better express their intent.
> - **Headline behavior — thought-like opacity:** suggestions ease *into* view gently
>   and fade away as a thought dissolves; non-intrusive, meditative, never abrupt.
> - Caret-anchored ghost text for the top suggestion + a separate, non-focus-stealing
>   suggestions surface for the ranked set; Tab accepts; Esc/other keys dismiss.
> - System-wide floating presentation over arbitrary apps; must never take keyboard
>   focus from the host app.
> - macOS-native (AppKit `NSPanel`/`NSWindow` + Core Animation, HIG type/spacing,
>   vibrancy materials, dark/light).
> - Accessibility: VoiceOver-navigable suggestions, a reduced-motion path that
>   replaces fades with instant/dissolve, reduced-transparency support.
> - Privacy-legible: an unobtrusive capture-active indicator; default-deny per-app
>   allowlist; no persistence.
> - Performance: 60 fps opacity animations, no main-thread stalls during analysis,
>   cancel stale work on new input.

---

## 7. Ready-to-run prompt (placeholders resolved)

Paste the original seven-section prompt with the two blocks above substituted for
`{{WRITING_CONTEXT}}` and `{{DESIGN_REQUIREMENTS}}`. Everything else in that prompt
(the scratchpad instruction, the seven required sections, the precision/measurement
requirements, and the poetic-tone requirement) stays verbatim. The author of the spec
should treat Sections 1–5 of *this* hand-off as binding context: the spec must extend
the existing ghost-text + panel architecture and the `AnalysisResult` contract, and
must explicitly note the `Suggestion.kind` schema addition needed for the three
suggestion types.
