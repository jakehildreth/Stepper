# ADR 0008: Test-StepperScript is standalone; Repair-StepperScript calls Test- internally; New-Step first-run calls Repair-

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

Three related concerns need to be addressed:

1. **Validation**: checking whether a script meets Stepper's structural requirements
2. **Repair**: fixing issues found during validation
3. **First-run hook**: `New-Step` currently calls `Test-StepperScriptRequirements` directly on first run to check/fix the calling script

Three design options for the relationship between validation and repair:

- **A. Independent**: `Test-` and `Repair-` share no code; both check and fix independently
- **B. Shared private helper**: both call a `Find-StepperScriptIssues` private function; repair adds the fix layer
- **C. Repair- calls Test-**: `Test-` is the source of truth; `Repair-` consumes its output and applies fixes

Option A duplicates detection logic. Option B is more modular but adds indirection for minimal benefit. Option C is the simplest directed composition: `Test-` has one job (find issues), `Repair-` has one job (fix what `Test-` found).

---

## Decision

- `Test-StepperScript` is standalone: takes a path, returns a structured result, never modifies files
- `Repair-StepperScript` calls `Test-StepperScript` internally: applies fixes for each fixable issue code, returns the post-fix `Test-StepperScript` result
- `New-Step` first-run replaces the direct `Test-StepperScriptRequirements` call with `Repair-StepperScript`
- `Test-StepperScriptRequirements` is deleted; it is a private function with no external callers

---

## Rationale

- `Test-` follows the PowerShell convention of returning data without side effects
- `Repair-` follows the convention of performing action and reporting result
- Callers who only want to check (not fix) can call `Test-` directly
- Callers who want to check AND fix in one call use `Repair-`
- First-run hook in `New-Step` needs repair semantics (it must fix, not just report)
- `Test-StepperScriptRequirements` was private with a single caller (`New-Step`), which is now updated; there is nothing to be backward-compatible with

---

## Consequences

- `Test-StepperScript` output shape: `{ Path, IsValid, Issues[] }`; never writes files
- `Repair-StepperScript` output: same shape as `Test-StepperScript`, reflects post-repair state
- `New-Step.ps1`: replace `Test-StepperScriptRequirements` call with `Repair-StepperScript -ScriptPath $scriptPath`
- `Test-StepperScriptRequirements.ps1` and its test file are deleted
