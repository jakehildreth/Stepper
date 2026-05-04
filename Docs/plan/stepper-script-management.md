# Plan: Stepper Script Management Functions

**Date:** 2026-05-01
**Status:** In Progress
**Author:** Jake Hildreth

---

## Summary

Add four public functions and two private helpers to improve the Stepper user experience:

1. `Test-StepperScript` : validate a script's Stepper compatibility, return structured results
2. `Repair-StepperScript` : fix issues found by Test-StepperScript, replace first-run repair hook
3. `Convert-StepperScript` : migrate plain variables to `$Stepper.<var>` via interactive AST-driven rewrite
4. `New-StepperScript` : create a new script pre-wired for Stepper use
5. (Private) `Find-CrossStepVariables` : AST analysis supporting Convert-StepperScript
6. (Private) `Add-StepperCbh` : CBH injection/augmentation supporting Repair-StepperScript

Refactor `New-Step` first-run behavior to call `Repair-StepperScript` directly.

---

## Phase 1: Private helpers

### `Private/Find-CrossStepVariables.ps1`

AST-walks all `New-Step` scriptblock bodies in a script. Finds variable names that are:
- Assigned (`AssignmentStatementAst`) in at least one step body, AND
- Referenced (`VariableExpressionAst`) in a DIFFERENT, later step body

Excludes:
- Variables already using `$Stepper.*` notation
- PowerShell automatic variables: `$_`, `$Error`, `$null`, `$true`, `$false`,
  `$PSVersionTable`, `$Host`, `$profile`, `$args`, `$input`, `$MyInvocation`,
  `$PSCmdlet`, `$PSBoundParameters`, `$PSDefaultParameterValues`, `$PSScriptRoot`,
  `$PSCommandPath`, `$ExecutionContext`, `$ConfirmPreference`, `$DebugPreference`,
  `$ErrorActionPreference`, `$VerbosePreference`, `$WarningPreference`,
  `$InformationPreference`, `$WhatIfPreference`, `$ProgressPreference`, `$PSStyle`

Returns: `[string[]]` of variable names (without `$`).

### `Private/Add-StepperCbh.ps1`

Inspects a script's AST for comment-based help via `ScriptBlockAst.GetHelpContent()`.

- If no CBH exists: inserts a full CBH block with `.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`
- If CBH exists but has no `.NOTES`: appends `.NOTES` section with Stepper usage blurb
- If `.NOTES` exists: appends Stepper usage blurb to the existing `.NOTES`
- Silent (no Write-Host, no user prompt); consistent with CmdletBinding injection
- Returns `$true` if the script was modified, `$false` otherwise

---

## Phase 2: `Test-StepperScript`

**File:** `Public/Test-StepperScript.ps1`

Standalone diagnostic function. Does NOT modify files.

### Output

```powershell
[PSCustomObject]@{
    Path    = [string]          # Resolved script path
    IsValid = [bool]            # $true if Issues array is empty
    Issues  = [PSCustomObject[]] # Array of issue objects
}
```

Each issue:
```powershell
[PSCustomObject]@{
    Code     = [string]  # e.g. 'MissingCmdletBinding'
    Message  = [string]  # Human-readable description
    Severity = [string]  # 'Error' | 'Warning' | 'Info'
}
```

### Issue codes

| Code | Severity | Fixable by Repair- |
|---|---|---|
| `MissingCmdletBinding` | Error | Yes |
| `MissingInstallGuard` | Error | Yes |
| `MissingCbh` | Warning | Yes |
| `MissingStopStepper` | Warning | No |
| `NoSteps` | Warning | No |

### Detection logic

- `MissingCmdletBinding`: `ParamBlock.Attributes` does not contain `CmdletBinding`
- `MissingInstallGuard`: no line matching `Install-Module\s+Stepper`
- `MissingCbh`: `ScriptBlockAst.GetHelpContent()` returns null
- `MissingStopStepper`: no `Stop-Stepper` `CommandAst` node in script
- `NoSteps`: no `New-Step` `CommandAst` nodes in script

---

## Phase 3: `Repair-StepperScript`

**File:** `Public/Repair-StepperScript.ps1`

Calls `Test-StepperScript` internally. Applies fixes for each fixable issue code.
Supports `-WhatIf` / `-Confirm` via `[CmdletBinding(SupportsShouldProcess)]`.

### Fix behavior

| Issue | Action |
|---|---|
| `MissingCmdletBinding` | Insert `[CmdletBinding()] param()` above first non-comment content |
| `MissingInstallGuard` | Insert install guard after param block |
| `MissingCbh` | Call `Add-StepperCbh` (silent) |
| `MissingStopStepper` | Write-Warning only, do not modify |
| `NoSteps` | Write-Warning only, do not modify |

Returns the `Test-StepperScript` result object (post-fix state).

---

## Phase 4: `New-Step` first-run refactor

**File:** `Public/New-Step.ps1`

Replace the direct call with `Repair-StepperScript -ScriptPath $scriptPath`. `Test-StepperScriptRequirements` is deleted (private, no external callers).

No user-visible behavior change.

---

## Phase 5: `Convert-StepperScript`

**File:** `Public/Convert-StepperScript.ps1`

### Parameters

```
Parameter Set 'ByPath':
  -Path [string] Mandatory

Parameter Set 'ByName':
  -Name [string] Mandatory
  -Directory [string] optional (defaults to $PWD)

Common:
  -OutputPath [string] optional (if absent: in-place + .bak backup)
  -Force [switch] skip interactive confirmation per-variable
  SupportsShouldProcess
```

### Algorithm

1. Resolve script path
2. Call `Find-CrossStepVariables` to get candidate list
3. If no candidates: write info, return
4. Present each candidate interactively (y/n/all/quit style)
5. Collect confirmed variable names
6. AST-walk: collect ALL `VariableExpressionAst` occurrences of each selected var
   that are INSIDE any `New-Step` scriptblock body, collect `Extent.StartOffset` and `Extent.EndOffset`
7. Sort occurrences by `StartOffset` descending (back-to-front rewrite preserves offsets)
8. Rewrite script text: replace `$varname` with `$Stepper.Varname`
9. Write output (in-place + .bak, or -OutputPath)
10. Print summary of changes made

### Scope restriction

Only rewrites occurrences INSIDE `New-Step` scriptblock bodies.
Does NOT rename occurrences outside step blocks (e.g. script-level code, param blocks).

---

## Phase 6: `New-StepperScript`

**File:** `Public/New-StepperScript.ps1`

### Parameters

```
Parameter Set 'ByPath':
  -Path [string] Mandatory

Parameter Set 'ByName':
  -Name [string] Mandatory
  -Directory [string] optional (defaults to $PWD)

Common:
  -Force [switch] overwrite if file exists
  -Showcase [switch] Aliases: -Full, -Detailed, -WithExamples
```

### Output

`[System.IO.FileInfo]`: the created file, for pipeline use.

### Templates

**Minimal (default):** CBH + `[CmdletBinding()] param()` + install guard + 2 placeholder steps + `Stop-Stepper`

**Showcase (-Showcase):** All of the above plus commented examples of:
- Named steps
- `$Stepper.<var>` persistence
- `-NoLog`
- `-Retry` with `-RetryInterval` and `-MaxRetries`
- `#region Stepper ignore` blocks

---

## Testing strategy

All tests written before implementation (TDD). Pester 5, `BeforeAll`/`Describe`/`Context`/`It`, AAA pattern.

For interactive functions (`Convert-StepperScript`), use `-Force` to bypass prompts in tests.

Regression gate: full existing suite must pass after Phase 4 refactor.

---

## Files created / modified

### New
- `Private/Find-CrossStepVariables.ps1`
- `Private/Add-StepperCbh.ps1`
- `Public/Test-StepperScript.ps1`
- `Public/Repair-StepperScript.ps1`
- `Public/Convert-StepperScript.ps1`
- `Public/New-StepperScript.ps1`
- `Tests/Find-CrossStepVariables.Tests.ps1`
- `Tests/Add-StepperCbh.Tests.ps1`
- `Tests/Test-StepperScript.Tests.ps1`
- `Tests/Repair-StepperScript.Tests.ps1`
- `Tests/Convert-StepperScript.Tests.ps1`
- `Tests/New-StepperScript.Tests.ps1`

### Modified
- `Public/New-Step.ps1`: first-run hook calls `Repair-StepperScript`
- `Private/Test-StepperScriptRequirements.ps1`: deleted (private, no external callers)
