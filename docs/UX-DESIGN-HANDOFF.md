# Lexicon — UI/UX Design Hand-off

**Purpose:** everything a designer or a fresh agent session needs to produce the
comprehensive UI/UX specification for Lexicon's suggestion surface, cold, without
prior conversation. Read §1–§3 for grounding, then run the prompt in §4.

---

## 1. Project state (cold-start brief)

**Lexicon** is a working, system-wide macOS writing companion (not a prototype).
It runs as a menu-bar accessory app and, in any allowlisted app, captures the user's
writing in real time, infers their communicative goal via the Claude API, and offers
suggestions that the user accepts inline with **Tab**.

Built and verified end-to-end (all live):
- **Capture** — `AXObserver` on the frontmost app's focused text element; ~350 ms
  debounce; default-deny per-app allowlist; secure fields excluded.
- **Analysis** — cascading model selection: Haiku 4.5 hot path (~2.0–2.5 s),
  escalating to Sonnet 4.6 / Opus 4.8 on low confidence or long input. Returns a
  typed `AnalysisResult { goalId, goalLabel, confidence, suggestions[] }`.
- **Surface (current, minimal)** — a borderless **caret-anchored ghost-text window**
  showing the top suggestion inline, plus a separate **floating `NSPanel`** listing
  ranked suggestions with rationale. Selecting a row re-arms the ghost.
- **Insert** — global `CGEventTap` swallows **Tab** when a suggestion is armed and
  performs **span replacement** via the Accessibility API (`kAXSelectedText`), with a
  clipboard-preserving ⌘V fallback. Smart spacing avoids run-together words.

**This hand-off designs the *experience* of that surface** — the part the backlog
calls "UI/UX polish." The plumbing exists; the look, motion, and interaction feel
do not yet. The critical new requirement is the **thought-like opacity behavior**:
suggestions should ease into view and dissolve like thoughts, never snapping.

### Where the current surface lives (to evolve, not discard)
- `Sources/Lexicon/OverlayController.swift` — `GhostTextWindow` (borderless,
  click-through, **never key**), `SuggestionsPanel` (`.nonactivatingPanel`, **never
  key**), and `OverlayController` (owns `armedSuggestion`, `present/arm/dismiss`).
- `Sources/Lexicon/CaretLocator.swift` — caret rect via
  `kAXBoundsForRangeParameterizedAttribute`, converted to Cocoa coordinates.
- `Sources/Lexicon/AnalysisResult.swift` — the data the UI renders.
- `Sources/Lexicon/Inserter.swift` — accept/insert behavior (Tab → span replace).
- Visual sandbox: `Lexicon --demo-ui` renders the panel with mock data and writes a
  PDF snapshot to `/tmp/lexicon-panel.pdf` — use it to iterate on visuals without AX
  or API calls.

---

## 2. Hard constraints the spec MUST honor (from the real implementation)

These are non-negotiable because they come from how the app actually works:

1. **Never steal focus.** Both windows are non-key / non-activating; the host app
   keeps keyboard focus (or inserts land in the wrong place). No design element may
   require the surface to become key.
2. **Two coordinated surfaces.** An *inline* ghost at the caret + a *separate* panel.
   The spec must treat these as one system (the panel's selection drives the ghost).
3. **Asynchronous, latency-variable arrival.** Suggestions appear ~2 s after a typing
   pause (Haiku), sometimes later (escalation). The motion design must make this delay
   feel intentional and calm, not laggy — this is *why* the thought-like fade fits.
4. **Caret-anchored, and the caret moves.** Positioning derives from AX caret bounds;
   AX-poor apps may return nothing (then the panel must still work, positioned
   independently). Handle "no caret rect" gracefully.
5. **System-wide over arbitrary apps.** The surface floats over Mail, Messages, Notes,
   docs — unknown backgrounds, light and dark. Contrast and legibility can't assume a
   known canvas.
6. **Privacy-forward.** Default-deny capture; a visible capture/pause affordance must
   exist. Nothing about the UI should imply always-on surveillance.
7. **Accept = Tab; non-key dismissal.** Tab accepts the armed suggestion; any other
   keystroke dismisses the ghost; Esc dismisses. Keep this; extend, don't replace.
8. **Reduced-motion path is mandatory**, precisely because motion is the signature —
   it must degrade to instant/opacity-only without losing usability.

---

## 3. Filled placeholders for the design prompt

Paste these into the `{{WRITING_CONTEXT}}` and `{{DESIGN_REQUIREMENTS}}` slots in §4.

### WRITING_CONTEXT
> Lexicon is used by a knowledge worker drafting everyday professional prose —
> emails in Mail, replies in Messages/Slack, notes and short documents — directly in
> whatever native macOS app they already use. They are not in a dedicated editor;
> Lexicon floats over their real writing surface. The register shifts by app and
> moment: formal and careful in a stakeholder email, loose and quick in a chat. The
> user wants in-the-moment help saying what they *mean* more precisely — sharper
> vocabulary, cleaner syntax, better cadence — without being pulled out of flow.
> Writing is often bursty (type a clause, pause, reconsider). Suggestions are
> inherently interruptive by nature, so the experience must feel ambient and
> opt-in: present when wanted, invisible when not, never a nag. The defining mood is
> *a quiet collaborator thinking alongside you* — thoughts that surface and recede.

### DESIGN_REQUIREMENTS
> 1. **Dual surface:** an inline, caret-anchored ghost completion (the single best
>    suggestion) plus a separate, non-activating floating panel that lists the full
>    ranked set with rationale. Neither may take keyboard focus.
> 2. **Three suggestion classes, visually distinct:** vocabulary expansion, syntax
>    improvement, and cadence/flow commentary. They must be told apart at a glance
>    (icon/color/label system) yet share one calm visual family.
> 3. **Thought-like opacity is the signature behavior:** suggestions ease in and
>    dissolve out like passing thoughts — gentle, non-linear, never abrupt. Specify
>    exact durations, delays, and easing curves; differentiate fade-in, dwell, and
>    fade-out, and the triggers for each.
> 4. **Flow-preserving interaction:** Tab accepts the armed suggestion; clicking a
>    panel row re-arms the ghost; Esc or continued typing dismisses gently. Ignored
>    suggestions fade rather than persist. Provide feedback (visual + optional haptic)
>    and full keyboard/accessibility alternatives.
> 5. **Real-time discipline:** appear after a contemplative pause (~350 ms debounce
>    plus ~2 s analysis), not on every keystroke; update or supersede gracefully as
>    text changes; never thrash during rapid typing.
> 6. **System-wide legibility:** must read over unknown light/dark app backgrounds,
>    align to macOS HIG (materials, vibrancy, SF type, control metrics), and respect
>    Dynamic Type, Increase Contrast, and Reduce Motion.
> 7. **Privacy-forward affordances:** a visible capture/pause indicator and a clear
>    "not capturing here" state; nothing that reads as covert.
> 8. **Latency as calm, not lag:** use the motion design to make the ~2 s analysis
>    delay feel like deliberate contemplation rather than slowness.

---

## 4. The design task (ready to run)

> You will be designing a comprehensive UI/UX specification for an AI-assisted writing
> assistant that takes the form of a macOS widget. This widget analyzes a user's
> writing in real-time and offers intelligent suggestions to help improve their work.
>
> Writing context — see WRITING_CONTEXT in §3 above.
> Design requirements — see DESIGN_REQUIREMENTS in §3 above.
>
> Create a complete UI/UX specification. Core functionality: real-time analysis of the
> user's writing; vocabulary expansion suggestions; syntax improvement recommendations;
> cadence and flow comments; all suggestions help expound and elucidate the user's
> intent and goals.
>
> **Critical visual behavior:** suggestions appear and disappear with opacity
> transitions that mimic the natural flow of thoughts — easing into view gently and
> fading away just as a thought does. Non-intrusive, almost meditative; thoughts
> naturally arising and dissolving.
>
> Before writing, use a `<scratchpad>` to think through: widget position relative to
> the writing area; prioritizing/displaying multiple simultaneous suggestions without
> overwhelm; the specific timing and easing curves that create the thought-like
> quality; helpfulness without distraction; macOS design-language/widget conventions;
> how the writing context and requirements shape the decisions.
>
> Then produce the specification inside `<design_specification>` tags, organized into
> exactly these seven sections — detailed and precise enough to mock up and implement
> from alone, with specific measurements (pt/px), timing (ms/s), and easing curves:
>
> 1. **Widget Layout & Positioning** — structure, dimensions, placement, spatial
>    relationship to the writing area; floating vs docked vs contextual.
> 2. **Visual Design** — color, typography, spacing, shadows, transparency, hierarchy;
>    aligned to Apple HIG.
> 3. **Suggestion Display System** — how vocabulary/syntax/cadence types are
>    distinguished; organization, grouping, prioritization when several appear.
> 4. **Animation & Transition Specifications** — fade-in duration/delay/easing; dwell
>    time at full opacity; fade-out duration/easing; fade-out triggers (time/action/
>    new content); hover/focus/interaction state changes.
> 5. **Interaction Patterns** — accept; dismiss; ignored behavior; visual + haptic
>    feedback; keyboard shortcuts and accessibility alternatives.
> 6. **Real-time Behavior** — when suggestions appear; how they update as the user
>    keeps typing; how they're replaced/removed when irrelevant; rapid typing vs pauses.
> 7. **Technical Considerations** — framework recommendation (note: WidgetKit can't
>    take live input — Lexicon uses AppKit/SwiftUI floating windows; see §2);
>    accessibility (VoiceOver, reduced motion); real-time performance; privacy/data
>    handling; system integration points.
>
> Honor the hard constraints in §2 of this hand-off. Maintain the poetic, thought-like
> quality throughout — the widget should feel like a natural extension of the user's
> creative process. Output only the `<scratchpad>` and `<design_specification>`.

---

## 5. Suggested starting values (optional — for the motion section)

Grounded in the "passing thought" brief and the ~2 s analysis latency. The designer
may revise, but these are defensible defaults to react to:

- **Fade-in:** 420 ms, `cubic-bezier(0.22, 1, 0.36, 1)` (gentle ease-out, like a
  thought surfacing); ghost and panel stagger by ~80 ms (ghost first).
- **Dwell:** ghost persists while armed (no auto-fade); the panel auto-dims to ~0.5
  opacity after 6 s of no interaction, recovering to 1.0 on cursor proximity/hover.
- **Fade-out:** 680 ms, `cubic-bezier(0.4, 0, 1, 1)` (slow ease-in to nothing, like a
  thought dissolving); triggered by accept, Esc, continued typing, or supersession.
- **Supersession:** new suggestion cross-fades (old out 300 ms / new in 420 ms,
  overlapping) rather than hard-swapping.
- **Reduce Motion:** replace all of the above with a 100 ms linear opacity step (no
  spatial movement, no stagger).
- **Type accents (one calm family):** vocabulary = system teal; syntax = system
  indigo; cadence/flow = system pink — each at low saturation over a `.hudWindow`
  material; never more than 6 rows; class shown by a leading SF Symbol + 11 pt label.

---

## 6. Definition of done for the design phase

A spec that (a) fills all seven sections with implementable detail, (b) never violates
§2, (c) specifies the thought-like motion concretely (durations + curves + triggers)
*and* its Reduce-Motion fallback, and (d) maps cleanly onto the existing
`OverlayController` two-window model so a developer can implement it by evolving the
current code rather than starting over.
