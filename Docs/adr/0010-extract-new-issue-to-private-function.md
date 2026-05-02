# ADR 0010: Extract New-Issue to Private/New-StepperIssue.ps1

**Date:** 2026-05-02
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`Test-StepperScript` originally contained a nested helper function `New-Issue` defined
inside the function body:

```powershell
function New-Issue {
    param([string]$Code, [string]$Severity, [string]$Message)
    [PSCustomObject]@{ Code = $Code; Severity = $Severity; Message = $Message }
}
```

This pattern has several problems:

1. **Redefined on every call** — PowerShell re-parses and rebinds the nested function
   definition each time `Test-StepperScript` is invoked. No caching, no reuse.
2. **Violates one-function-per-file** — project convention (enforced for `New-StepperScript`
   in the same codebase) requires each function to live in its own `.ps1` file.
3. **No `[CmdletBinding()]`** — the nested function lacks the required attribute, making it
   a simple function rather than an advanced function. No common parameters, no
   `$PSCmdlet` support.
4. **No comment-based help** — undiscoverable and undocumented.
5. **No `ValidateSet` on `$Severity`** — callers could pass any string; the private file
   adds `[ValidateSet('Error', 'Warning')]` to enforce the domain values.
6. **Not independently testable** — nested scope means it cannot be dot-sourced or
   unit-tested in isolation.

Two alternatives were considered:

- **Inline the `[PSCustomObject]@{}` at each call site** — removes the function entirely
  but duplicates the object shape at 5 call sites. Harder to change the shape later.
- **Extract to `Private/New-StepperIssue.ps1`** — single source of truth, independently
  testable, follows project conventions, gets `[CmdletBinding()]` and CBH for free.

---

## Decision

Extract `New-Issue` to `Private/New-StepperIssue.ps1` as `New-StepperIssue`.

Rename adds the `Stepper` namespace prefix consistent with all other private helpers
(`New-StepperIssue` vs `New-Issue`). The `-Stepper` infix makes the private helper
clearly scoped to this module when it appears in stack traces or `Get-Command` output
during module development.

`Test-StepperScript` dot-sources it via the module's private glob in `Stepper.psm1`.
The test file's `BeforeAll` dot-sources it explicitly alongside the other private files.

---

## Consequences

- `Test-StepperScript` is simpler — no nested function definition in the body.
- `New-StepperIssue` is independently testable if issue-object shape ever needs to change.
- `[ValidateSet('Error', 'Warning')]` on `$Severity` makes invalid severity strings a
  parse-time error rather than a silent bug.
- All call sites in `Test-StepperScript` updated from `New-Issue` to `New-StepperIssue`.
