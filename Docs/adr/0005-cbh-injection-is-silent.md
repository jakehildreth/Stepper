# ADR 0005: CBH injection on first run is silent

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`Repair-StepperScript` (and the first-run hook in `New-Step`) detects whether a user's script has comment-based help (CBH). If CBH is absent, Stepper can inject a skeleton block automatically.

Two injection styles were considered:
1. **Silent**: inject without prompting; emit one `Write-Verbose` call; continue execution
2. **Interactive**: print a notice, call `exit`, require user to re-run (same pattern as `MissingCmdletBinding` in the old `Test-StepperScriptRequirements`)

The `[CmdletBinding()]` and install-guard injections are already silent as of ADR 0003. CBH injection modifies the script in the same category of "structural improvement" as those two, and carries no functional risk (CBH is inert at runtime).

Unlike missing `[CmdletBinding()]` (which would cause runtime errors if absent), missing CBH never breaks script execution. The exit-and-rerun pattern is justified when the modification changes runtime behavior. CBH does not.

---

## Decision

CBH injection is silent. No `Write-Host`, no `exit`, no user prompt. Consistent with the `[CmdletBinding()]` and install-guard injection behavior.

---

## Rationale

- CBH is documentation-only; its absence or presence does not affect script execution
- Interrupting execution for a non-functional change violates the principle of least surprise
- Consistency with existing silent injections (ADR 0003); users learn one mental model
- Verbose output is still emitted, so `-Verbose` users see what happened

---

## Consequences

- `Add-StepperCbh` emits `Write-Verbose` when it modifies a script, nothing else
- `Repair-StepperScript` does not `exit` after CBH injection
- `MissingCbh` issue code has `Severity = 'Warning'` (not `'Error'`) in `Test-StepperScript` output
