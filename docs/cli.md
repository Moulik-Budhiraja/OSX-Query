## Non-Interactive Interactions

Run an action against one matched result by index:

```bash
axorc --app TextEdit --selector "AXButton[AXTitle*=\"Save\"]" \
  --result-index 1 --interaction click
```

Supported `--interaction` values:

- `click`
- `press`
- `focus`
- `set-value` (requires `--interaction-value`)
- `send-keystrokes-submit` (requires `--interaction-value`)

Related flags:

- `--result-index` is 1-based and required for interactions
- `--submit-after-set-value` is valid only with `set-value`
  - flow: click target -> set value -> press Return

Implementation notes:

- `send-keystrokes-submit` sends text, then submits with Command+Return.
- click/focus flows can activate the owning app before action.

## Interactive Mode (`-i`)

Interactive mode runs in a full-screen TUI and requires a TTY.

Main controls:

- Query mode: type selector, `Enter` run, `q` clear
- Results mode:
  - move: `j`/`k`, arrows, `PageUp/PageDown`, `Ctrl+B/Ctrl+F`
  - jump: `gg` top, `G` bottom
  - search: `/`, then `n` / `N`
  - `Enter` opens interaction menu
  - `q` back to query editing
- Interaction menu:
  - `c` click
  - `p` press
  - `f` focus
  - `v` set-value
  - `s` set-value-submit
  - `k` send-keystrokes-submit

`-r` / `--refocus-terminal` can return focus to your terminal after click/focus/submit interactions.

## Cache Session Mode

For repeated queries on the same app/process:

```bash
# warm cache + query
axorc --app TextEdit --selector "AXButton" --cache-session

# reuse warm snapshot without refresh
axorc --app TextEdit --selector "AXButton[AXTitle*=\"Save\"]" --use-cached
```

Validation is strict when reusing cache:

- same app PID
- cached depth must be deep enough
- cached attributes must cover selector requirements

The cache daemon uses a per-user Unix socket under `/tmp` and exits after idle timeout.

## AX Exposure Mode

Some apps require explicit AX attribute toggles before rich tree access.

```bash
axorc --enable-ax com.apple.TextEdit
```

What it does:

- finds a running process for the bundle id
- focuses candidate app
- sets:
  - `AXEnhancedUserInterface = true`
  - `AXManualAccessibility = true`
- restores original frontmost app focus
- prints one summary line (`ax_exposure ...`)
