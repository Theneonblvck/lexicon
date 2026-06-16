# AGENTS.md — Lexicon

Guidance for human and AI contributors working in this repository.

## 1. Purpose

Lexicon is a **system-wide macOS writing companion** (menu-bar app). It captures text from allowlisted apps via Accessibility APIs, infers communicative intent through a Claude model cascade, shows caret-anchored ghost text plus a suggestions panel, and inserts the armed suggestion on **Tab**.

All five build steps are implemented. See `README.md` for user-facing setup and verification.

## 2. Read This First

Before making changes, read in this order:

1. `README.md` — build, permissions, verification commands
2. `BACKLOG.md` — deferred UX/product decisions (post-baseline)
3. `docs/UX-SPECIFICATION.md` — visual/interaction spec (signature: thought-like opacity)
4. `docs/UX-DESIGN-HANDOFF.md` — design constraints for UI polish work

## 3. Repo Map

```
Sources/Lexicon/          # All Swift source (single executable target)
  main.swift              # Entry: menu-bar app + headless CLI modes
  AppDelegate.swift       # Wires capture → router → overlay → event tap
  AppState.swift          # Permissions, pause, foreground-app tracking
  AppConfig.swift         # Model IDs, API key resolution, bundle identity
  CaptureEngine.swift     # AXObserver, debounced CaptureEvents, allowlist gate
  CaptureEvent.swift      # Debounced text + caret snapshot
  AllowlistStore.swift    # Default-deny per-app capture allowlist + audit log
  AnalysisRouter.swift    # Haiku → Sonnet cascade; cancels in-flight on new input
  ClaudeAPIClient.swift   # Anthropic Messages API → AnalysisResult JSON
  AnalysisResult.swift    # goalId, goalLabel, confidence, [Suggestion]
  OverlayController.swift # GhostTextWindow + SuggestionsPanel
  CaretLocator.swift      # AX caret → Cocoa screen rect
  EventTapController.swift# CGEventTap: Tab accepts when armed, else passes through
  Inserter.swift          # AX span replace / smart insert / clipboard-preserving paste
  StatusBarController.swift # Menu bar UI, permissions, allowlist, pause
  PermissionsManager.swift  # TCC checks + grant prompts
  Keychain.swift            # API key storage
  FileLog.swift             # Dev log to /tmp/lexicon-capture.log
  Demo.swift                # --demo-ui mock overlay → PDF
Resources/Info.plist        # Bundle metadata (LSUIElement, bundle id)
build-app.sh                # swift build + .app assembly + codesign
setup-signing.sh            # Stable self-signed identity for persistent TCC grants
docs/                       # UX spec and design handoff
```

Build artifacts (do not edit): `.build/`, `build/Lexicon.app/`

## 4. Architecture (data flow)

```
Focused app (allowlisted)
  → CaptureEngine (AXObserver, 350ms debounce)
  → CaptureEvent
  → AnalysisRouter (tier1 Haiku, escalate to Sonnet on low confidence / long text)
  → ClaudeAPIClient
  → AnalysisResult
  → OverlayController (ghost + panel at caret)
  → User presses Tab (EventTapController, only when armed)
  → Inserter (AX span replace → smart insert → paste fallback)
```

### Model cascade (`AppConfig.swift`, `AnalysisRouter.swift`)

| Tier | Model | When |
|------|-------|------|
| 1 | `claude-haiku-4-5-20251001` | Default hot path, every tick |
| 2 | `claude-sonnet-4-6` | Confidence &lt; 0.6, or input &gt; ~2400 chars |
| 3 | `claude-opus-4-8` | Explicit deep rewrite only (`requestDeepRewrite`) |

API key: `LEXICON_API_KEY` env var → Keychain (`com.lexicon.app.apikey` / `anthropic`). Never hardcode.

## 5. Dev Setup

**Requirements:** macOS 14+, Swift 5.9+ (`Package.swift`).

```sh
./build-app.sh              # release build → build/Lexicon.app
open build/Lexicon.app      # menu-bar app (accessory, no dock icon)
```

Foreground run (NSLog + FileLog):

```sh
build/Lexicon.app/Contents/MacOS/Lexicon
tail -f /tmp/lexicon-capture.log
```

### Headless verification (no GUI, no Accessibility)

```sh
# One analysis against live API
LEXICON_API_KEY="sk-ant-..." \
  build/Lexicon.app/Contents/MacOS/Lexicon --analyze "your draft text"

# Force a specific model tier
LEXICON_TEST_MODEL=claude-sonnet-4-6 build/Lexicon.app/Contents/MacOS/Lexicon --analyze "..."

# Overlay UI mock → /tmp/lexicon-panel.pdf
build/Lexicon.app/Contents/MacOS/Lexicon --demo-ui

# Clipboard-preserving paste fallback
build/Lexicon.app/Contents/MacOS/Lexicon --selftest-clipboard
```

### Permissions (required for live loop)

1. **Accessibility** — read focused text in other apps
2. **Input Monitoring** — intercept Tab via CGEventTap

App stays **inert** until both are granted. After `./setup-signing.sh`, TCC grants survive rebuilds; ad-hoc signing drops grants each build.

Env affordances (off by default):

- `LEXICON_PROMPT_ON_LAUNCH=1` — surface Accessibility prompt on launch
- `LEXICON_TEST_MODEL` — override model in `--analyze` mode

## 6. Core Engineering Rules

1. **Privacy first.** Default-deny allowlist; never read secure/password fields; no keystroke reconstruction; minimal text sent to API over TLS; no persistence beyond live session.

2. **Never steal focus.** Ghost window is click-through; suggestions panel is non-activating; overlay must not become key/main.

3. **Tab semantics.** Intercept Tab **only** when a suggestion is armed. Any other key dismisses ghost; unarmed Tab passes through.

4. **Insertion strategy** (`Inserter.swift`): span replacement when `original` is set → smart additive insert at caret → clipboard-preserving ⌘V fallback.

5. **Cancel in-flight analysis** when new capture arrives (`AnalysisRouter`).

6. **API client minimalism** (`ClaudeAPIClient.swift`): no temperature/thinking params; model returns raw JSON matching `AnalysisResult`; tolerant decode for `Suggestion.kind`.

7. **Keep changes scoped.** This is a single-target Swift package — no frameworks, no tests dir yet. Match existing patterns (FileLog, NSLog, weak self in closures).

8. **Signing material** lives in `.signing/` (gitignored). Do not commit certs/keys.

## 7. Key Types

```swift
struct AnalysisResult { goalId, goalLabel, confidence, suggestions }
struct Suggestion { kind, original?, replacement, rationale }
enum SuggestionKind { vocabulary, syntax, cadence }  // cadence is display-only
struct CaptureEvent { text, caretRange, bundleId, appName, timestamp }
```

## 8. Verification Before Hand-off

Minimum checks for behavior changes:

```sh
./build-app.sh
build/Lexicon.app/Contents/MacOS/Lexicon --selftest-clipboard   # must print PASS
# With API key configured:
build/Lexicon.app/Contents/MacOS/Lexicon --analyze "test sentence"
```

For UI changes: `--demo-ui` and compare against `docs/UX-SPECIFICATION.md`.

For capture/analysis integration: grant permissions, allowlist an app, `tail -f /tmp/lexicon-capture.log`, type in allowlisted app.

## 9. Current Backlog Themes

See `BACKLOG.md`. Highest-signal deferred items:

- UI polish (thought-like opacity, caret-following ghost, onboarding)
- True span replacement at scale; Tab vs dedicated accept key tradeoff
- Stable signing → notarization → DMG distribution
- Cost controls (delta gate, cache unchanged text, rate-limit backoff)

## 10. What Not To Do

- Do not bypass TCC or read from non-allowlisted apps
- Do not add keystroke logging as a capture fallback without explicit product decision
- Do not hardcode API keys or commit `.signing/` material
- Do not make the overlay steal focus from the host app
- Do not send sampling/thinking params that Anthropic rejects on these models
