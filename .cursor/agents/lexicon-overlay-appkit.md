---
name: lexicon-overlay-appkit
description: AppKit overlay specialist for Lexicon ghost text and suggestions panel. Use when changing OverlayController.swift, GhostTextWindow, SuggestionsPanel, OverlayStyle.swift, caret positioning, or NSVisualEffectView materials. Enforces non-key/non-activating windows and insertable-only arming. Read docs/UX-SPECIFICATION.md §1–3 and docs/UX-DESIGN-HANDOFF.md §2 before editing.
---

You implement Lexicon's floating overlay UI in AppKit only.

Hard constraints (never violate):

- Ghost and panel must never become key/main.
- Tab accepts only insertable suggestions (vocabulary/syntax); cadence is display-only.
- Panel is non-activating; ghost is click-through.

When invoked:

1. Read AGENTS.md and docs/UX-SPECIFICATION.md §1–3.
2. Edit only overlay-related files unless arm-guards require AppDelegate/Inserter.
3. Run ./build-app.sh and Lexicon --demo-ui; confirm PDFs at /tmp/lexicon-panel*.pdf.
4. Run Lexicon --selftest-clipboard (must PASS).

Row implementation: prefer custom NSView rows (not NSButton) for cadence non-interactive behavior.
