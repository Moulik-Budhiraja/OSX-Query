---
name: axorc
description: Use as a computer-use tool when an agent must interact with desktop UIs, web apps, or browser workflows via AXORC. Apply for querying UI element trees, resolving stable references, and executing actions with verification; also use in automated tests where UI interaction is required to validate other systems or end-to-end behavior. Enforce screenshot-first verification for meaningful state changes and non-undoable actions.
---

# AXORC

## Purpose

Use AXORC as a computer-use tool when an agent must interact with desktop UIs, browser/web workflows, or UI-driven test flows used to validate other systems.
When browser interaction is required, use the user's default browser unless the user explicitly asks for a specific browser.

## Mandatory Pre-Read (Do Not Skip)

Read both documents in full before executing any `axorc` command:
- [AXORC Query Usage](references/axorc-query-usage.md)
- [AXORC Actions Usage](references/axorc-actions-usage.md)

If either file is missing at these relative paths, stop and locate them first. Do not execute `axorc` until both are read completely.
Treat those two usage docs as the source of truth for all command syntax, workflow sequencing, and troubleshooting details.

## Screenshot-First Policy (Required)

Screenshot verification is mandatory for AXORC workflows with meaningful state transitions.
Do not continue action execution when required screenshots are missing.

Capture screenshots at these checkpoints:
- Before the first action in any new page/view/dialog context.
- After every action that is expected to change UI state meaningfully.
- Both before and after non-undoable, high-impact, or destructive actions (delete, submit, close, overwrite, send).
- Before acting when selector results are ambiguous or multiple candidates look similar.

Screenshot file handling:
- Use the macOS `screencapture` CLI to take required screenshots.
- Save screenshots to temporary directories by default (for example, under `/tmp`).
- Clean up screenshot files after verification is complete.
- Keep screenshots only when the user explicitly asks to retain them.

Execution blockers:
- If screenshot evidence does not clearly confirm the intended target, stop and re-query before acting.
- If post-action screenshots do not match expected outcomes, stop, reassess, and do not chain further actions blindly.
