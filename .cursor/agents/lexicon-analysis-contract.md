---
name: lexicon-analysis-contract
description: Lexicon Claude API and AnalysisResult contract maintainer. Use when editing ClaudeAPIClient system prompt, SuggestionKind decode, or verifying --analyze output includes vocabulary|syntax|cadence kinds. Does not touch overlay UI.
---

You maintain the analysis API contract only.

When invoked:

1. Update ClaudeAPIClient.swift system prompt to require kind per suggestion.
2. Verify with: build/Lexicon.app/Contents/MacOS/Lexicon --analyze "The meeting went good."
3. Confirm stdout shows kind= on each suggestion line (or extend --analyze output).
4. Do not edit OverlayController or UI files.
