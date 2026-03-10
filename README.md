# OSXQuery

OSXQuery is a macOS CLI for querying and interacting with Accessibility trees with a css-like query language.

It is built for fast UI inspection and automation by agents from the terminal, with a selector-driven query language and an action language for sending input to matched elements.

## Overview

- Query running apps with a compact selector syntax
- Inspect results from the focused app, app name, bundle id, or PID
- Reuse cached snapshots for faster repeated queries
- Send actions like click, text entry, hotkeys, scroll, and drag
- Explore the tree interactively in a full-screen TUI

## Installation

Install the CLI globally with npm:

```bash
npm i -g osx-query
```

Recommended: install the agent skill as well:

```bash
npx skills add Moulik-Budhiraja/OSX-Query
```

After install:

```bash
osx --help
```

## Usage

Query the focused app for buttons:

```bash
osx query --app focused "AXWindow AXButton"
```

Example output (truncated):

```text
stats app=focused selector="AXWindow AXButton" elapsed_ms=588.62 traversed=2470 matched=129 shown=10
AXButton ref=04fa2fd1f name="Hide sidebar" desc="Hide sidebar"
AXButton ref=86106af38 name="Button"
AXButton ref=fa89acf01 name="axorcist"
AXButton ref=f016e3f4c name="Open"
...
```

Render the focused app's matches as a tree:

```bash
osx query --app focused "AXWindow AXButton" --tree
```

Example output (truncated):

```text
stats app=focused selector="AXWindow AXButton" elapsed_ms=613.23 traversed=2597 matched=144 shown=50
AXButton ref=02fbe8b7c name="ax-view-monitor" desc="ax-view-monitor"
├── AXButton ref=de770416d name="Collapse folder" desc="Collapse folder"
└●─ AXButton ref=b3ce745d9 name="Start new thread in ax-view-monitor" desc="Start new thread in ax-view-monitor"
...
```

Query with a warm cache session so results include refs you can act on:

```bash
osx query --app com.apple.Messages "AXButton" --cache-session
```

Click a result using the `ref=...` value returned by the cached query:

```bash
osx action 'send click to 28e6a93cf;'
```

Send text as keystrokes to a cached result:

```bash
osx action 'send text "hello world" as keys to 28e6a93cf;'
```

Open the interactive selector UI:

```bash
osx interactive com.apple.Messages
```

## Notes

- macOS only
- The app executing `osx` needs Accessibility permission to inspect and interact with apps
- Some workflows may also require optional Screen Recording permission for the app executing `osx` to take screenshots
- If queries return nothing useful, grant Accessibility access to the terminal app or host app running `osx`

## Acknowledgments

OSXQuery builds on foundations established in Peter Steinberger's [AXorcist](https://github.com/steipete/AXorcist).
