# Lexicon — Backlog

Deferred until the end-to-end loop (Steps 1–5) is verified. Triage after that.

## Step-5 design decisions baked in (revisit if they bite)
- **Tab conflict:** Tab is intercepted *only when a suggestion is armed*; otherwise it
  passes through as a normal Tab. Esc (and any non-Tab key) dismisses the ghost so a
  "real" Tab follows on the next press. → Revisit: a dedicated accept key (e.g. ⌘↩) to
  avoid ever shadowing Tab.
- **No cycling (yet):** Tab accepts the top suggestion; choosing another is click-only in
  the panel. → Revisit: ⌥↑/↓ or repeated-Tab to cycle ghost candidates before accept.
- **Insertion = caret insert via `kAXSelectedText`** with clipboard-preserving ⌘V
  fallback. → Revisit: true *span replacement* (locate & replace the `original` text,
  not just insert `replacement` at the caret).

## UI / UX polish (post-baseline)
> Design hand-off (fills the brief, lists hard constraints, ready-to-run prompt):
> [docs/UX-DESIGN-HANDOFF.md](docs/UX-DESIGN-HANDOFF.md). The thought-like opacity
> motion is the signature requirement.

- Visual theme for the panel + ghost (typography, spacing, dark/light, accent).
- Caret-following ghost that updates as the caret moves; fade in/out animation.
- Onboarding flow: guided permission grant, allowlist first-run, "try it" sample.
- Preferences window: model-tier overrides, debounce, allowlist management, hotkeys.
- Click-to-accept in the panel (currently selection only re-arms; Tab accepts).
- Accept history + undo; show what was replaced.
- Confidence-gated UI (hide panel below a threshold; subtle vs prominent modes).

## Feature expansion
- True span replacement and multi-edit apply (apply several suggestions at once).
- Tier-3 "deep rewrite" surface (a command/hotkey that rewrites the whole sentence).
- Per-app tone profiles (formal in Mail, casual in Messages).
- Streaming partial suggestions for lower perceived latency.
- Broader capture coverage for AX-poor apps (Electron/web views): keystroke-reconstruction
  fallback was rejected in design (keylogger risk) — revisit only with strong consent UX.
- Telemetry (local-only) for acceptance rate to tune thresholds.

## Cost / performance (load-bearing for the live loop — partly addressed in Step 5)
- Min text-delta + idle gate before firing an API tick (don't analyze on every pause).
- Cache/skip when text is unchanged; cancel in-flight on new input (done in router).
- Token budgeting; cap suggestions; back off on rate limits.

## Productization
- Stable code-signing identity so the Accessibility/Input-Monitoring grants survive
  rebuilds (currently ad-hoc → grant drops every rebuild; self-signed cert needs a
  password-gated trust step). Then notarization + a real app icon + DMG.
