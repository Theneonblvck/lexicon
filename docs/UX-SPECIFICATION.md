# Lexicon — UI/UX Specification

> Produced from `docs/UX-DESIGN-HANDOFF.md` §4. Honors the §2 hard constraints and
> maps onto the existing `OverlayController` two-window model.

<scratchpad>
**Positioning.** Lexicon floats over the user's real app, so the surface can't be a
docked sidebar or a WidgetKit tile — it must be contextual and caret-anchored. Two
pieces, already in code: an inline ghost *at* the caret (the single best edit, where
the eye already is) and a separate panel *near* the caret (the fuller, ranked set +
rationale + cadence commentary). The ghost is where flow lives; the panel is where
deliberation lives. The panel must sit off the active line so it never occludes the
words being written — below-and-right by default, flipping above when the caret is low
on screen. It should re-anchor on each new analysis, not chase every caret movement
(chasing = jitter = the opposite of meditative).

**Many suggestions without overwhelm.** Rank dominates because Tab accepts the top
item — so the list is rank-ordered, not grouped by class; class is carried by a quiet
accent (symbol + hue), not by sectioning. Cap at 6. Crucially, three classes behave
differently: vocabulary and syntax are *insertable edits* (have a replacement, Tab
works); cadence/flow are *observations* (no insertion) — they must look like comments,
not accept-able rows, or the user will Tab into confusion. The ghost only ever mirrors
the top *insertable* suggestion.

**Thought-like timing.** A thought surfaces softly and dissolves slowly. So fade-in is
quicker and eased-out (arrives, settles); fade-out is longer and eased-in (lingers,
then lets go). Asymmetry is the whole trick. A few points of upward drift sells
"rising/receding." The ~2 s analysis latency is reframed by this: the calm fade makes
the wait feel like the assistant *thinking*, not the app *lagging*. Per-row cascade
(thoughts arriving one after another) and a gentle auto-dim after dwell (a thought
receding but not yet gone) complete the metaphor. All of it must collapse to a 100 ms
opacity step under Reduce Motion — the signature can't become an accessibility wall.

**Helpful, not distracting.** Never steal focus (hard constraint — inserts would land
wrong). Never appear mid-burst; only in the pause. Auto-dim rather than auto-vanish so
glancing back is possible. Make dismissal cost nothing: keep typing and it dissolves.

**macOS conventions.** SF type, `NSVisualEffectView` materials + vibrancy, system
accent semantics, `controlSize`, Dynamic Type, Increase Contrast, Reduce Motion,
trackpad haptics. Non-activating panels (`.nonactivatingPanel`) so the host app stays
key — this is already how the code works.

**Context's pull.** Bursty professional writing across light/dark unknown canvases →
legibility can't assume a background (inner scrim + material), register varies (tone is
neutral), and the mood is "a quiet collaborator," which is exactly what the soft motion
encodes.
</scratchpad>

<design_specification>

## 1. Widget Layout & Positioning

**Form.** Two coordinated, **floating, non-activating** surfaces — never docked, never
a WidgetKit tile (WidgetKit cannot receive live keystrokes). Both are contextual to the
caret.

**A. Ghost completion (inline).** A borderless, click-through window rendering the top
*insertable* suggestion as faint inline text.
- Anchored to the caret rectangle from `kAXBoundsForRangeParameterizedAttribute`.
- Origin: `x = caretRect.maxX + 2 pt`, baseline aligned to the caret; height =
  `max(textHeight, caretRect.height)`.
- Matches host font size when derivable from the focused element; fallback **13 pt**.
- `ignoresMouseEvents = true`; never key/main.

**B. Suggestions panel (separate).** A soft floating card listing the ranked set.
- **Width:** 320 pt fixed. **Height:** intrinsic, capped to 6 rows (~max 340 pt).
- **Corner radius:** 12 pt. **Padding:** 14 pt all sides; 8 pt inter-row.
- **Default anchor:** below-and-right of the caret — origin
  `(caretRect.minX, caretRect.minY − panelHeight − 12 pt)` in Cocoa coords (i.e. 12 pt
  *below* the caret line so the active line is never covered).
- **Flip rule:** if the panel would clip the screen's bottom, place it 12 pt *above*
  the caret line instead. Clamp horizontally to keep 8 pt off screen edges.
- **Re-anchor cadence:** repositions only when a *new* analysis arrives — not on every
  caret move (prevents jitter). If the caret leaves the analyzed line, the panel fades.
- **No-caret fallback (AX-poor apps):** panel anchors to the lower-trailing corner of
  the active screen, 16 pt inset; the ghost is suppressed (nothing to anchor to).

**C. Menu-bar item (exists).** Status + capture indicator + pause + allowlist. The
persistent, always-available control surface; the floating pieces are ephemeral.

**Spatial logic.** Ghost = flow (at the words). Panel = deliberation (beside the
words). The user's eye never has to leave the line to accept the best edit (Tab); the
panel is there only when they choose to consider alternatives.

---

## 2. Visual Design

**Material & elevation.**
- Panel background: `NSVisualEffectView`, material `.hudWindow`, `state = .active`,
  `blendingMode = .behindWindow`, emphasized. Over it, a 1 pt inner scrim
  (`NSColor.windowBackgroundColor` at 0.18 alpha) guarantees legibility over unknown
  light/dark canvases.
- Shadow: y-offset 8 pt, blur 24 pt, color black @ 0.18 (light) / 0.40 (dark).
- Hairline border: 0.5 pt `separatorColor` for edge definition on busy backgrounds.

**Typography (SF Pro Text, Dynamic Type–scaled).**
- Header (goal label): 13 pt semibold, `labelColor`. Confidence pill: 11 pt medium,
  `secondaryLabelColor`, trailing.
- Suggestion replacement: 13 pt semibold, `labelColor`.
- Original span (struck/quoted): 12 pt regular, `tertiaryLabelColor`.
- Rationale: 11 pt regular, `secondaryLabelColor`, max 2 lines, wraps.
- Cadence/flow comment: 12 pt **italic**, `secondaryLabelColor` (signals "observation,
  not edit").
- Ghost text: host size (fallback 13 pt), `tertiaryLabelColor` at **0.45** opacity.

**Color — one calm family, low saturation, three class accents** (semantic, adapt to
light/dark):
| Class | Accent | SF Symbol | Insertable |
|---|---|---|---|
| Vocabulary | system **teal** | `textformat.abc` | yes |
| Syntax | system **indigo** | `curlybraces` | yes |
| Cadence/flow | system **pink** | `waveform` | no (comment) |

Accent appears only as the 14×14 pt leading symbol and a 2 pt leading rule on the
armed row — never as a filled background (keeps it meditative, not loud).

**Spacing & hierarchy.** Header → 8 pt → rows. Each row: `[symbol] [replacement]` on
line 1, `[rationale]` on line 2, 2 pt leading accent rule. The **armed** row gets a
`.selectedContentBackgroundColor` @ 0.12 fill + full accent rule. Visual weight order:
armed replacement > other replacements > rationale > original > cadence comments.

**Transparency.** Panel material translucent (~0.85 effective); text always full
opacity within the surface (the *surface* fades, never the glyph contrast). Increase
Contrast → drop the material for solid `windowBackgroundColor` + 1 pt opaque border.

---

## 3. Suggestion Display System

**Data model addition.** Each `Suggestion` gains a `kind: vocabulary | syntax | cadence`
(extend `AnalysisResult.swift`; the analyzer prompt classifies each item). Cadence
items may have `replacement == nil` (pure comment).

**Distinction.** Class is read at a glance via leading symbol + accent hue + (for
cadence) italic comment styling. No section headers — the list stays a single calm
column.

**Organization & prioritization.**
1. **Rank-ordered by `confidence`/impact**, best first — because Tab accepts the top
   *insertable* item. Class does not re-sort.
2. **Cap = 6 rows.** Overflow is dropped (not paginated) with a 11 pt
   `tertiaryLabelColor` footer "+N more" — Lexicon favors quiet over completeness.
3. **Ghost mirror:** the inline ghost always shows the top *insertable* suggestion
   (skip cadence comments). If only cadence items exist, no ghost shows — the panel
   presents observations alone.
4. **Cadence rows are non-interactive for Tab**: they render as comments (italic, no
   hover-accept affordance) and are skipped by the accept/cycle keyboard model.

**Multiple simultaneous suggestions** never stack as competing popovers — they are one
ranked list in one panel, arriving as a soft per-row cascade (see §4), so "many"
reads as "a settling sequence of thoughts," not a wall.

---

## 4. Animation & Transition Specifications

All motion is **opacity-led**, with a small companion **vertical drift** that reads as
rising/receding. Implemented with Core Animation on the windows' layers
(`NSWindow.alphaValue` + `contentView.layer` transform), driven by `NSAnimationContext`.

**Easing curves (the thought metaphor lives here — asymmetric on purpose):**
- **Surface (fade-in):** `cubic-bezier(0.22, 1.00, 0.36, 1.00)` — gentle ease-out; a
  thought arriving and settling.
- **Dissolve (fade-out):** `cubic-bezier(0.40, 0.00, 1.00, 1.00)` — slow ease-in to
  nothing; a thought lingering, then releasing.

**Fade-in.**
- Ghost: opacity 0 → 0.45, **360 ms**, surface curve; drift +4 pt → 0.
- Panel: starts **+80 ms** after the ghost (ghost leads). Container opacity 0 → 1,
  **420 ms**; drift +6 pt → 0.
- **Per-row cascade:** each row +**30 ms** after the previous (rows 1–6 → 0–150 ms
  internal stagger), each 280 ms surface curve. Reads as thoughts arriving in sequence.

**Dwell (full opacity).**
- Ghost: persists at 0.45 **while armed** (no auto-fade — it's the live target).
- Panel: full opacity for **6.0 s** of no interaction, then auto-dims to **0.55** over
  **900 ms** (surface curve) — "receding, not gone." Recovers to 1.0 over **220 ms** on
  hover, cursor within **24 pt**, panel-row navigation, or a new analysis.

**Fade-out.**
- Duration **680 ms**, dissolve curve; drift 0 → −3 pt (sinks as it dissolves).
- Panel rows reverse-cascade out at **24 ms** stagger (last row leaves first).
- **Triggers:**
  - *Accept* (Tab/click) — armed row flashes its accent @ 0.24 for 120 ms, then the
    whole surface dissolves (680 ms).
  - *Esc* — immediate dissolve.
  - *Continued typing* — any text delta beyond the analyzed snapshot dissolves the
    ghost immediately and the panel over 680 ms (superseded if new analysis lands).
  - *Supersession* — new analysis arrives: **cross-fade** — old dissolves 300 ms while
    new fades in 420 ms, overlapping ~120 ms (no hard swap).
  - *Relevance loss* — a single suggestion whose `original` span no longer exists fades
    that row only (300 ms), list re-flows.
  - *Focus loss* (host app deactivates) — dissolve 680 ms.

**Interaction-state changes.**
- Hover a row: row opacity → 1.0 (220 ms), 2 pt accent rule brightens, 1 pt baseline
  accent underline fades in.
- Arm change (cycle/click): outgoing row underline fades out 160 ms; incoming armed
  fill + rule fade in 200 ms; ghost cross-updates its text with a 200 ms opacity dip
  (0.45 → 0.18 → 0.45) so the swap reads as a thought changing, not a flicker.

**Reduce Motion** (`accessibilityDisplayShouldReduceMotion`): replace *all* of the
above with a **100 ms linear** opacity step (0↔target). No drift, no cascade, no
auto-dim, no cross-fade (instant swap). Dwell/auto-dim disabled (panel stays at full
opacity until a discrete trigger).

---

## 5. Interaction Patterns

**Accept.**
- **Tab** inserts the **armed** suggestion (top insertable by default, or the
  panel-selected one) via span replacement (`Inserter.swift`). Tab is swallowed by the
  `CGEventTap` only while armed; otherwise it passes through as a normal Tab.
- Feedback: armed-row accent flash (120 ms) → surface dissolve; **haptic**
  `NSHapticFeedbackManager.alignment` (trackpad only); optional VoiceOver announcement
  "Inserted: <replacement>".

**Re-arm / choose another.**
- Click a panel row, or **⌥↓ / ⌥↑** to cycle the armed suggestion (skips cadence
  comments). The ghost updates to the newly armed text (200 ms opacity-dip swap). No
  insertion until Tab.

**Dismiss.**
- **Esc** dissolves both surfaces. Any **non-Tab keystroke** dissolves the ghost
  immediately (typing wins); the panel dissolves over 680 ms unless superseded.

**Ignore.**
- Doing nothing: panel auto-dims to 0.55 after 6 s and stays as a faint presence;
  continued typing dissolves it. Ignoring is free and silent — the core of the
  non-intrusive promise.

**Feedback summary.**
| Action | Visual | Haptic |
|---|---|---|
| Accept | accent flash → dissolve | `.alignment` |
| Arm change | dip-swap ghost, row underline | none |
| Hover | row → full opacity + underline | none |
| Dismiss | dissolve | none |

**Keyboard & accessibility alternatives.**
- Tab (accept), ⌥↑/⌥↓ (cycle), Esc (dismiss) — all via the event tap, so they work
  without the surface ever holding focus.
- **VoiceOver:** on arrival, post a *polite* `NSAccessibility` announcement — goal +
  top suggestion + count. Panel rows expose `accessibilityLabel`
  ("<kind>: replace <original> with <replacement>; <rationale>") and
  `accessibilityHelp`. A global hotkey (default **⌃⌥Space**) moves VO focus into the
  panel for row-by-row review; Esc returns focus to the host.
- Honors Dynamic Type (row heights intrinsic), Increase Contrast (solid surface), and
  Reduce Motion (§4).

---

## 6. Real-time Behavior

**Appearance.** Suggestions appear only after a **contemplative pause**: a **350 ms**
idle debounce after the last keystroke, then analysis (~2.0–2.5 s on the Haiku hot
path). They never appear mid-keystroke. The ~2 s wait is intentionally *un-indicated*
by a spinner — the calm fade-in *is* the "thinking" signal (no progress chrome, per the
meditative brief).

**Updating as the user types.** Continued typing immediately dissolves the current
ghost (the user is past it). When the next pause triggers a fresh analysis, the new set
**cross-fades** in over the old (§4). In-flight requests are cancelled on new input
(already implemented), so only the latest pause produces a surface.

**Replacement / removal of irrelevant suggestions.** When new text invalidates a
suggestion's `original` span, that row fades out individually (300 ms) and the list
re-flows; if the whole snapshot is stale, the panel cross-fades to the new analysis.
Caret leaving the analyzed line fades the panel.

**Rapid typing vs. contemplative pauses.** During fast typing the debounce + request
cancellation suppress *all* surfaces — Lexicon stays silent and out of the way. The
moment the user pauses to think, the assistant's thoughts surface alongside theirs.
This is the core rhythm: **silence in the burst, presence in the pause.**

---

## 7. Technical Considerations

**Framework.** **AppKit `NSWindow` (ghost, borderless) + `NSPanel`
(`.nonactivatingPanel`, panel)**, with SwiftUI content hosted via `NSHostingView`, and
**Core Animation** for opacity/drift. **Not WidgetKit** — it cannot receive live
keystrokes or anchor to an arbitrary app's caret (the §2 constraint). Both windows
return `false` from `canBecomeKey`/`canBecomeMain` so the host app keeps focus.

**Caret & geometry.** `kAXBoundsForRangeParameterizedAttribute` →
`CaretLocator.caretCocoaRect`; nil → no-caret fallback (§1). Coalesce caret queries to
the analysis cadence; never poll per-frame.

**Accessibility.** Reduce Motion → 100 ms linear (§4). Increase Contrast → solid
surface + opaque border. VoiceOver announcements + labeled rows + the ⌃⌥Space review
hotkey (§5). Full Dynamic Type scaling. All color via semantic system colors so
light/dark/contrast adapt for free.

**Performance.** Analysis is already off the main thread; keep all animation on the CA
layer (no main-thread layout in the fade loop). Reuse row views; cap at 6. Debounce
(350 ms) + in-flight cancellation bound API cost and prevent surface thrash. Target:
surface fade-in begins ≤ 16 ms after a result is delivered (one frame).

**Privacy & data handling.** Default-deny per-app allowlist; a visible capture
indicator (menu-bar dot: filled = capturing here, hollow = allowed-but-paused, none =
not allowed). A distinct **"not capturing here"** resting state (no ghost, menu shows
the app isn't allowlisted). Captured text is never persisted; only the minimal snapshot
is sent over TLS; the API key lives in Keychain. Nothing in the UI implies always-on
surveillance — presence is tied to the allowlist and the pause toggle.

**System integration.** Accessibility (capture + insert) and Input Monitoring (the Tab
`CGEventTap`); pasteboard-preserving ⌘V fallback when AX insertion is unsupported;
menu-bar `NSStatusItem` for status/pause/allowlist. Stable code-signing identity
(`setup-signing.sh`) so TCC grants persist across builds.

</design_specification>
