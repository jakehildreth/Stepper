# ADR 0003: Silent auto-add for script requirements with `-SkipRequirementsCheck` escape hatch

**Date:** 2026-04-24
**Status:** Superseded by ADR-0008
**Deciders:** Jake Hildreth

---

## Context

`Test-StepperScriptRequirements` checks whether a user's script declares `#requires -Modules Stepper` and `[CmdletBinding()]`. When either is missing, it blocks execution with an interactive `Read-Host` prompt offering to add them, skip, or quit. If the user chooses to add, the declarations are inserted and `exit` is called to force a re-run from scratch.

This behavior is problematic:

1. **Blocks automation**: any CI/CD pipeline or unattended run hangs indefinitely waiting for interactive input.
2. **Surprises users**: an unexpected halt mid-execution on first run violates the principle of least surprise.
3. **Violates module design principles**: `Read-Host` is explicitly against Stepper's non-interactive design pattern.
4. **"Skip" is a footgun**: silently continuing without the required declarations causes unpredictable failures downstream, making it the worst option despite being the easiest to reach.

The only safe response in the old dialog was always "Add". The "Skip" and "Quit" paths offer false choice.

---

## Decision

Replace the interactive prompt with silent auto-add behavior:

- If declarations are missing, add them and return `$true` without any user prompt.
- Emit one `Write-Verbose` call per declaration added.
- Delete any existing state file (same as before; the script has structurally changed).
- Add a `-SkipRequirementsCheck` `[switch]` parameter to `New-Step` for callers who want to bypass the check entirely.

---

## Rationale

Silent auto-add preserves the original intent (ensure the script is properly structured) while eliminating interactive friction. Since "Add" was the only safe option in the old prompt, auto-add is semantically equivalent to the old default. `Write-Verbose` satisfies observability without blocking execution; users running with `-Verbose` see exactly what changed.

The `-SkipRequirementsCheck` escape hatch gives advanced users who consciously manage their own declarations a clean opt-out, without requiring workarounds or file hacks.

---

## Consequences

- `Private/Test-StepperScriptRequirements.ps1`: remove `Read-Host` and all prompt UI; add `Write-Verbose` calls for each declaration added; auto-add unconditionally.
- `Public/New-Step.ps1`: add `-SkipRequirementsCheck [switch]` parameter; skip the `Test-StepperScriptRequirements` call when set.
- `Tests/Test-StepperScriptRequirements.Tests.ps1`: remove all "user chooses X" contexts; add assertions that `Read-Host` is never called and `Write-Verbose` is called when additions are made.
- `Tests/New-Step.Tests.ps1`: add context verifying `-SkipRequirementsCheck` suppresses the requirements check.
