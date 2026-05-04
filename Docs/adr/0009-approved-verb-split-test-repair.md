# ADR 0009: Approved verb split: Test-StepperScript and Repair-StepperScript; Validate- rejected

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

The initial feature request used "Validate-StepperScript" as a working name for the function that checks whether a script is correctly structured for Stepper.

`Validate` is not in the PowerShell approved verb list (`Get-Verb` returns no match for `Validate`). Using an unapproved verb causes `Test-ModuleManifest` warnings and breaks `PSScriptAnalyzer` lint rules. It also confuses tab-completion and discoverability.

The approved verbs covering the intended semantics are:
- `Test-` : performs a check and returns a result (boolean or structured)
- `Repair-` : fixes something that is broken or incomplete

Both semantics are needed: users may want to check without modifying (CI pipeline, pre-flight review), and users may want to automatically fix issues (first-run hook, developer setup).

---

## Decision

- `Validate-StepperScript` is rejected
- `Test-StepperScript` handles the validation-only use case
- `Repair-StepperScript` handles the validation + repair use case
- Both are public functions

---

## Rationale

- `Test-` is the correct approved verb for "check and return a result" (`Test-Path`, `Test-Connection`, `Test-ModuleManifest`)
- `Repair-` is the correct approved verb for "fix a known issue" (`Repair-Volume`, `Repair-Item`)
- Splitting the concerns into two functions gives callers explicit control over whether modifications occur
- `PSScriptAnalyzer` will pass; `Import-Module` will not warn about unapproved verbs
- Consistent with how the rest of the PowerShell ecosystem handles "check vs fix" (e.g. `Test-Disk` vs `Repair-Volume`)

---

## Consequences

- No `Validate-StepperScript` function is created at any point
- `Test-StepperScript` is exported in `Stepper.psd1` `FunctionsToExport`
- `Repair-StepperScript` is exported in `Stepper.psd1` `FunctionsToExport`
- Both appear in `Export-ModuleMember -Function '*'` via `Stepper.psm1`
