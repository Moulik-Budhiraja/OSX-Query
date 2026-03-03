# AXORC OXQ Advanced Learnings (Query + Actions)

This guide is for readers with no prior chat context.
It documents both APIs:
- OXQ query API (`--app ... --selector ...`)
- OXA actions API (`--actions '...'`)

## 1. Current architecture
- Query mode discovers elements and emits refs.
- Actions mode runs programs against daemon-cached refs.
- Required lifecycle is `query+` then `action*`.
- Ref actions do not execute against raw query stdout.
- One global daemon is reused across calls.

## 2. OXQ query grammar (supported)

Supported selector features:
- Type selectors: role (`AXButton`) and wildcard (`*`)
- Combinators: descendant (` `), child (`>`)
- Attribute operators: `=`, `*=`, `^=`, `$=`
- Pseudos: `:has(...)`, `:not(...)`
- Selector lists: comma-separated OR

Practical grammar constraints:
- Attribute values must be quoted strings.
  - Invalid: `AXButton[enabled=true]`
  - Valid: `AXButton[enabled="true"]`
- One attribute group per compound.
  - Invalid: `AXButton[CPName="x"][enabled="true"]`
  - Valid: `AXButton[CPName="x",enabled="true"]`
- Unknown pseudos are rejected.

## 3. OXQ aliases and matching behavior

Useful aliases for matching:
- `CPName` (or `ComputedName`) is the most reliable text field.
- Also useful: `role`, `title`, `value`, `description`, `identifier`, `enabled`, `focused`.

Matching reminders:
- String matching is case-sensitive.
- Result de-duplication is by underlying AX element identity, not visible text.
- Distinct elements can share similar names and still behave differently.

## 4. Query command shape and options

Core shape:
```bash
axorc --app <target> --selector "<query>" [options]
```

Most useful query options:
- `--limit <n>`: reduce noise while exploring.
- `--cache-session`: refresh/warm daemon snapshot from live UI.
- `--use-cached`: run query against warm snapshot (no refresh).
- `--show-path`: include full path for disambiguation.
- `--show-name-source`: show computed-name source.
- `--max-depth <n>`: optional traversal cap, use sparingly.

Targeting tips:
- Prefer bundle IDs for stable app targeting.
- `focused` can be convenient for ad-hoc local checks.

## 5. High-leverage query patterns

Pattern 0: broad discovery pass
```bash
axorc --app <target> --selector 'AXTextField,AXTextArea,AXComboBox' --limit 80
axorc --app <target> --selector '*[CPName*="<keyword>"]' --limit 80
```

Pattern A: refine then verify
```bash
axorc --app net.imput.helium \
  --selector '*[CPName="In the news"]:not(AXStaticText)' \
  --limit 20 --show-path
```

Pattern B: contextual targeting with `:has(...)`
```bash
axorc --app net.imput.helium \
  --selector 'AXGroup:has(AXHeading[CPName="In the news"]) AXLink' \
  --limit 120
```

Pattern C: exclusion hygiene with `:not(...)`
```bash
axorc --app net.imput.helium \
  --selector 'AXLink[CPName*="Diddy Blud"]:not([CPName*="Go to channel"])'
```

Pattern D: role-first, text-second
```bash
AXButton[CPName^="Play"]:not([enabled="false"])
```

## 6. Using `:has(...)` effectively

When to use it:
- Parent-level targeting: find containers/windows with a descendant marker.
- Context disambiguation: same label appears in multiple regions.
- Relative structure matching: enforce direct-child shape with `>`.

Core forms:
```bash
# Parent has any matching descendant
AXWindow:has(AXTextArea[CPName*="Ask anything"])

# Parent has direct child
AXGroup:has(> AXTextArea[CPName*="Ask anything"])

# Contextual result matching
AXGroup:has(AXLink[CPName*="<context>"]) AXLink[CPName*="<target>"]
```

Tips:
- Keep the inner selector specific (role + text/attribute).
- If too broad, add another constraint or a `:not(...)`.

## 7. Query workflow playbook
1. Start with broad discovery (`AXTextField,AXTextArea,AXComboBox` or `*[CPName*="..."]`).
2. Narrow with role + `CPName` + `:not(...)`.
3. Add context with `:has(...)` when ambiguity remains.
4. Verify candidate set (`--limit`, then `--show-path`).
5. Warm refs with `--cache-session` before action phase.
6. Use `--use-cached` for non-interaction follow-up queries only.

## 8. `--actions` grammar reference

An actions program is a semicolon-terminated statement list.

Supported statements:
```txt
send text "..." to <ref>;
send text "..." as keys to <ref>;
send click to <ref>;
send right click to <ref>;
send drag <srcRef> to <dstRef>;
send hotkey <chord> to <ref>;
send scroll up|down|left|right to <ref>;
send scroll to <ref>;
read <attributeName> from <ref>;
sleep <milliseconds>;
open "AppNameOrBundleID";
close "AppNameOrBundleID";
```

Ref format:
- Exactly 9 hex chars (example: `063701895`).

Note:
- Clicks can sometimes miss, so its a good idea to try again, maybe with a more precise selector before completely changing approach.

## 9. Hotkey spec (current)

Format:
```txt
send hotkey <modifiers+base> to <ref>;
```

Modifiers (optional, unique, first):
- `cmd`
- `ctrl`
- `alt`
- `shift`
- `fn`

Base key (required, last, exactly one):
- Single alphanumeric: `a-z`, `0-9`
- Function keys: `f1` to `f24`
- Named keys:
  - `enter`
  - `tab`
  - `space`
  - `escape`
  - `backspace`
  - `delete`
  - `home`
  - `end`
  - `page_up`
  - `page_down`
  - `up`
  - `down`
  - `left`
  - `right`

Examples:
```bash
send hotkey enter to 063701191;
send hotkey cmd+a to 063701895;
send hotkey cmd+down to 065701701;
send hotkey shift+tab to 063701895;
```

## 10. Text entry modes

`send text "..." to <ref>;`
- Good first attempt for standard text fields.
- Uses focus fallback + value-setting behavior.
- Can be unreliable in rich editors.

`send text "..." as keys to <ref>;`
- Types like per-key input.
- Preferred for rich editors and punctuation-sensitive content.

## 10b. Additional action modes

`send right click to <ref>;`
- Right-clicks the element center (context menu path).

`send scroll to <ref>;`
- Calls AX `AXScrollToVisible` on the target element.
- No visibility pre-check and no wheel-scroll fallback.
- If unavailable or it fails, action returns an explicit runtime error.

`read <attributeName> from <ref>;`
- Reads and prints the full attribute value. (can be ussful to grep from)
- Supports aliases including `CPName`.

## 11. Cache, refs, and phase boundaries

Best-practice policy:
1. Start a phase with `--cache-session`.
2. Use `--use-cached` for back-to-back read-only queries.
3. After any UI-changing action, run a fresh `--cache-session`.

This is the reliable loop:
```txt
query (--cache-session) -> action program -> query (--cache-session) -> ...
```

Validated behavior:
- `query+` then `action*` is strictly required for ref actions.
- Refs are ephemeral and can go stale quickly.

## 12. Timing strategy
- Start with `sleep 100` for intra-program waits.
- Avoid trailing sleeps by default.
- Increase above 100 only when behavior proves unstable.

## 13. Quoting and parser pitfalls
- `send text` string literals are double-quoted.
- Nested unescaped double quotes can break parsing.
- For embedded quoted phrases, either escape carefully or use single quotes in content.

Example:
```bash
axorc --actions "send text \"He stated deep concern for 'a significant number of children and civilians' ...\" as keys to 0637027b0;"
```

## 14. Failure modes and fixes
- `No cached query snapshot available`
  - Run a new query with `--cache-session`.
- `Unknown element reference`
  - Re-query to refresh refs.
- Action returns `ok` but UI did not change
  - Re-verify target, focus, and post-action state with query/screenshot.
- Text missing in editor
  - Switch from `send text ... to` to `send text ... as keys to`.
- `AXScrollToVisible is not supported for <ref>`
  - Target element does not expose that AX action.
- `AXScrollToVisible failed for <ref>: ...`
  - AX action failed at runtime; re-query and validate the ref and UI state.

## 15. End-to-end starter template
```bash
# 1) Warm refs from current UI
axorc --app net.imput.helium \
  --selector 'AXTextField[AXDescription*="Address and search bar"],AXWebArea' \
  --cache-session --limit 20

# 2) Navigate
axorc --actions 'send text "https://en.wikipedia.org/wiki/Main_Page" to 063701191; send hotkey enter to 063701191;'

# 3) Re-query after UI change
axorc --app net.imput.helium \
  --selector 'AXHeading[CPName="In the news"],AXLink' \
  --cache-session --limit 200

# 4) Click target link
axorc --actions 'send click to 072701121;'

# 5) Continue with query/action loop
axorc --app net.imput.helium --selector 'AXWebArea,AXHeading' --cache-session --limit 60
```

## Advanced usage. 

- In rare cases, to exfiltrate data from browsers, it can be useful to open dev tools
