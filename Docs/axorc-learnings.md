# AXORC Learnings (Actions API first)

This file captures the practical defaults that worked repeatedly in live usage.

## Core model
- Use selector mode to discover refs.
- Use actions mode to do work on those refs.
- Treat action success as transport-level only; always verify with a query or screenshot.

Core query shape:
```bash
axorc --app <target> --selector "<query>" [--cache-session|--use-cached] [--limit N]
```

Core action shape:
```bash
axorc --actions '<statement>; <statement>; ...'
```

## Daily workflow (recommended)
1. Query with `--cache-session` to warm/update refs.
2. Run one short action program with those refs.
3. Re-query with `--cache-session` after any UI-changing action.
4. Use `--use-cached` only for back-to-back read-only follow-up queries.

Example:
```bash
# Warm refs on current UI
axorc --app net.imput.helium --selector 'AXTextField,AXWebArea' --cache-session

# Act
axorc --actions 'send text "https://en.wikipedia.org/wiki/Main_Page" to 063701191; send hotkey enter to 063701191;'

# UI changed => refresh refs
axorc --app net.imput.helium --selector 'AXWebArea,AXLink' --cache-session --limit 80

# No action in between => use cached for fast refinement
axorc --app net.imput.helium --selector 'AXLink[CPName*="In the news"]' --use-cached
```

## Query API quick guidance

Most useful query options:
- `--limit <n>`: cap rows and reduce noise while exploring.
- `--cache-session`: refresh refs from live UI.
- `--use-cached`: refine queries quickly when no interaction happened.
- `--show-path`: disambiguate similar matches by context/path.
- `--show-name-source`: debug where `CPName` came from.

Selector defaults that work well:
```bash
# Broad discovery
AXTextField,AXTextArea,AXComboBox
*[CPName*="<keyword>"]

# Stable browser address bar
AXTextField[AXDescription*="Address and search bar"]

# Contextual narrowing
AXGroup:has(AXHeading[CPName='In the news']) AXLink
AXLink[CPName*="<target>"]:not([CPName*="Go to channel"])
```

Query posture:
- Start broad, then narrow with role + `CPName` + context.
- Verify candidate sets before acting (`--limit`, then `--show-path` if needed).
- Keep using `--use-cached` until an action or UI change occurs.

## Validated learnings (high-confidence)
- `query+` then `action*` is strictly required for ref-based actions.
- Refs are ephemeral; refresh before critical phases.
- `--use-cached` is ideal for non-interaction follow-up queries.
- After any interaction or expected UI change, refresh with `--cache-session`.
- `sleep 100` is a good default; increase only when needed.
- Avoid trailing sleeps unless there is a concrete reason.
- Prefer bundle IDs for app activation (`open "net.imput.helium"`, `open "com.microsoft.Word"`).
- `send text "..." to <ref>` can be unreliable in rich editor surfaces but should be used for the first attempt at typing.
- `send text "..." as keys to <ref>` is the reliable path for rich editors and punctuation.
- `send scroll to <ref>` uses AX `AXScrollToVisible` only (no wheel-scroll fallback).

## Action statements used most often
```bash
# App lifecycle
open "net.imput.helium";
close "com.microsoft.Word";

# Element actions
send click to <ref>;
send text "..." to <ref>;
send text "..." as keys to <ref>;
send hotkey cmd+a to <ref>;
send scroll down to <ref>;
send scroll to <ref>;
sleep 100;
```

## Fast troubleshooting
- `No cached query snapshot available`: run a fresh `--cache-session` query first.
- `Unknown element reference`: refs are stale; re-query with `--cache-session`.
- Action executed but UI did not change: use screenshot + re-query to verify target and state.
- Text did not appear in editor: switch from `send text ... to` to `send text ... as keys to`.
- `AXScrollToVisible is not supported for <ref>`: target element does not expose that AX action.
- `AXScrollToVisible failed for <ref>: ...`: AX action call failed at runtime; re-query and verify target context.
