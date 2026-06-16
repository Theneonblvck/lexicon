# Lexicon

A **system-wide macOS writing companion**. Wherever you type — any app — Lexicon
ingests your writing in real time, infers what you're trying to express (a
structured *goal*), surfaces higher-precision vocabulary in a separate panel, and
lets you accept a suggestion inline with **Tab**.

> **Build status — all 5 steps implemented.**
> The app runs system-wide: it captures text in real time from allowlisted apps,
> analyzes intent via the Claude cascade (Haiku → Sonnet → Opus), renders
> caret-anchored ghost text plus a suggestions panel, and inserts the armed
> suggestion on **Tab** via a global event tap (clipboard-preserving fallback).
> It stays **inert** until Accessibility + Input Monitoring are granted and at
> least one app is allowlisted.
>
> Dev/verification entry points (no GUI needed):
> - `Lexicon --analyze "<text>"` — one live analysis (key from env/Keychain).
> - `Lexicon --demo-ui` — overlay UI with mock data → PDF at `/tmp/lexicon-panel.pdf`.
> - `Lexicon --selftest-clipboard` — verifies the paste fallback preserves the clipboard.

## Architecture (planned, 5-step chain)

| Step | Subsystem | Status |
|------|-----------|--------|
| 1 | Foundations & permissions (menu bar, TCC gates, config, Keychain) | ✅ |
| 2 | System-wide capture engine (AXObserver, secure-field exclusion, default-deny allowlist) | ✅ |
| 3 | Analysis router + cascade API client (Haiku → Sonnet → Opus) | ✅ |
| 4 | Caret-anchored ghost text + separate suggestions panel | ✅ |
| 5 | Global Tab interception (CGEventTap) + end-to-end integration | ✅ |

### Runtime model cascade
Each analysis tick routes to the cheapest sufficient model (configured in
`Sources/Lexicon/AppConfig.swift`, all swappable):

- **Tier 1** `claude-haiku-4-5-20251001` — hot path, every tick (<800ms target)
- **Tier 2** `claude-sonnet-4-6` — escalate on low confidence / long span / ambiguity
- **Tier 3** `claude-opus-4-7` — on-demand deep rewrite only

## Prerequisites

- macOS 14 or later
- Xcode command-line tools / Swift 5.9+ (`swift --version`)

## Build & run

```sh
./build-app.sh            # compiles + assembles build/Lexicon.app (ad-hoc signed)
open build/Lexicon.app    # launches the menu-bar app
```

For logs during development, run the binary in the foreground instead:

```sh
build/Lexicon.app/Contents/MacOS/Lexicon
```

A `text.cursor` icon appears in the menu bar. The menu shows live permission
status and lets you grant each permission.

## Permissions

Lexicon needs two macOS privacy grants to operate system-wide. It **never**
bypasses TCC and stays inert until both are granted:

1. **Accessibility** — to read the focused text element of other apps (Step 2).
   Menu → *✗ Accessibility — Grant…* → approve in
   **System Settings → Privacy & Security → Accessibility**.
2. **Input Monitoring** — to intercept the **Tab** key via a CGEventTap (Step 5).
   Menu → *✗ Input Monitoring — Grant…* → approve in
   **System Settings → Privacy & Security → Input Monitoring**.

After approving, reopen the menu (permissions are re-checked on open) — the marks
flip to **✓** and Status changes from *inert* to *active*.

### Stable signing (grants survive rebuilds)

By default the build is **ad-hoc** signed, whose code hash changes every build — so
macOS drops the Accessibility / Input Monitoring grants on each rebuild. To make the
grants persist, create a stable self-signed identity once:

```sh
./setup-signing.sh          # generates a dev cert + signing keychain
# then approve the one-time "trust this cert for code signing" password prompt
```

After that, `build-app.sh` signs with a **stable designated requirement**
(`identifier "com.lexicon.app" and certificate leaf = H"…"`), so you grant the two
permissions **once** and every future rebuild keeps them. The signing material lives
in `.signing/` (gitignored). The trust step adds a code-signing-only trust setting
for the `Lexicon Dev` cert to your user trust store.

## Verifying capture (Step 2)

The capture engine writes a development log to `/tmp/lexicon-capture.log` so you can
watch it work:

1. Grant **Accessibility** to Lexicon (above), then **relaunch** Lexicon — TCC only
   takes effect on a fresh launch.
2. Allowlist an app: focus e.g. TextEdit, then Lexicon menu → **Capture in TextEdit**.
3. `tail -f /tmp/lexicon-capture.log` and type in TextEdit — you'll see
   `capture app=TextEdit len=… caret=… text="…"`. Type in a non-allowlisted app and
   nothing is logged.

Dev affordances (env vars, both off by default in normal use):
- `LEXICON_PROMPT_ON_LAUNCH=1` — surface the Accessibility prompt on launch and
  register the app in the Accessibility list.

> **Re-granting after a rebuild:** the app is ad-hoc signed, so each rebuild changes
> its code hash and macOS drops the Accessibility grant. After a rebuild, toggle
> Lexicon off/on in **Privacy & Security → Accessibility** (requires your password)
> and relaunch. A stable signing identity would remove this; it's noted as future work.

## API key (used from Step 3 on)

The Anthropic API key is read **only** from the environment or the Keychain —
never hardcoded:

```sh
# Option A: environment variable
export LEXICON_API_KEY="sk-ant-..."

# Option B: Keychain (service com.lexicon.app.apikey, account anthropic)
security add-generic-password -s com.lexicon.app.apikey -a anthropic -w "sk-ant-..."
```

*About Lexicon…* in the menu reports whether a key is currently configured.

### Verifying analysis (Step 3)

A headless mode runs one analysis against the live API and exits — no menu-bar app,
no Accessibility needed:

```sh
LEXICON_API_KEY="$(security find-generic-password -s com.lexicon.app.apikey -a anthropic -w)" \
  ./build/Lexicon.app/Contents/MacOS/Lexicon --analyze "your draft text here"
```

Set `LEXICON_TEST_MODEL` to force a specific cascade tier (e.g. `claude-sonnet-4-6`).
The runtime cascade itself (Haiku hot path → Sonnet on low confidence / long input →
Opus on explicit deep-rewrite) lives in `AnalysisRouter.swift`.

## Using it end-to-end

1. `./build-app.sh && open build/Lexicon.app` — the menu-bar icon appears.
2. Grant **Accessibility** and **Input Monitoring** (menu → Grant…), then **relaunch**
   (TCC only takes effect on a fresh launch).
3. Store your API key (`security add-generic-password -s com.lexicon.app.apikey -a anthropic -w 'sk-ant-…'`).
4. Focus a third-party app (e.g. TextEdit), then Lexicon menu → **Capture in <app>**.
5. Type. Within ~350ms of a pause, Lexicon analyzes intent, shows the goal +
   suggestions panel, and ghosts the top suggestion at the caret.
6. Press **Tab** to insert the armed suggestion (or click another in the panel to
   re-arm it first). Any other key dismisses the ghost; Tab then behaves normally.

## Privacy posture

- **Default-deny capture:** from Step 2, capture is OFF in every app except those
  you explicitly add to an allowlist; an audit log records every approval.
- **Secure fields are never read** (password fields are excluded).
- Captured text is not persisted beyond the live session and only the minimal
  necessary text is sent to the API over TLS.
- A global **Pause capture** toggle is always available in the menu.
