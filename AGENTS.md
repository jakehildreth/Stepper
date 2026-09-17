# Agent Instructions

This project uses **GitHub Issues** for issue tracking. Repository: `jakehildreth/Stepper`.

## Issue Tracking

Use the GitHub CLI for task tracking; do not use beads, TodoWrite, TaskCreate, or markdown TODO lists.

```bash
gh issue list --repo jakehildreth/Stepper --state open
gh issue view <number> --repo jakehildreth/Stepper
gh issue create --repo jakehildreth/Stepper --title "..." --body-file ...
gh issue comment <number> --repo jakehildreth/Stepper --body-file ...
gh issue edit <number> --repo jakehildreth/Stepper ...
gh issue close <number> --repo jakehildreth/Stepper
```

Use existing `wayfinder:*` labels for Wayfinder maps and tickets. Before creating an issue, check for an existing issue covering the same work.

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` to fail instead of prompting
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

## Session Completion

Before ending a work session:

1. File GitHub Issues for remaining work.
2. Run relevant quality gates when code changed.
3. Update GitHub Issue status and comments.
4. Check `git status` and report any uncommitted changes.

Do not commit or push unless the user explicitly requests it.

## Build & Test

Use the repository's existing PowerShell/Pester test suite. Run the smallest targeted test command that covers the change.

## Architecture Overview

Stepper is a PowerShell module. Public commands live in `Public/`, private helpers in `Private/`, and Pester tests in `Tests/`. `Start-Stepper` owns script initialization and integrity checks; `New-Step` executes resumable step blocks.

## Conventions & Patterns

Prefer PowerShell AST parsing over regex for script analysis. Keep changes surgical, add or update focused Pester tests for behavior changes, and preserve existing script templates and ignore-region conventions.
