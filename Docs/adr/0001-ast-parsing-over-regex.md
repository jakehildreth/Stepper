# ADR 0001: AST-based script parsing over regex

**Date:** 2026-04-19
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

Stepper analyzes user scripts at runtime to locate `New-Step` and `Stop-Stepper` calls, count steps, extract step names, identify unmanaged code blocks, and detect `<#..#>` comment spans. All of this was implemented by scanning raw text lines with regex patterns.

Three categories of fragility were identified:

1. **Structural detection:** `New-Step` regex requires `{` on the same line as the call, breaking if the scriptblock is on the next line. Manual brace-counting to find block end does not account for `{`/`}` inside strings or heredocs.
2. **Comment span detection:** `<#` / `#>` are matched line-by-line, which breaks if either token appears after executable code on the same line.
3. **Executable-line classification:** A 5-pattern regex whitelist (`[CmdletBinding(`, `param(`, `using`, etc.) is used to skip "non-executable" lines. Incomplete by construction — any pattern not in the list is a false positive.

Additionally, the step-counting + name-listing logic is copy-pasted verbatim 3 times in `New-Step.ps1` (lines 349–371, 501–529, 713–740), and the script file is read from disk 2–3 times per `New-Step` execution.

---

## Decision

Replace all structural regex with `[System.Management.Automation.Language.Parser]` AST queries and token stream inspection.

Introduce a new private function `Get-ScriptAst` that:
- Calls `[Parser]::ParseFile()`, returning `[PSCustomObject]@{ Ast; Tokens; Errors }`
- Emits `Write-Warning` per parse error and returns the partial AST (callers decide whether to abort)
- Maintains a module-scoped `$script:astCache` hashtable keyed on `"$ScriptPath:$hash"` (using the existing `Get-ScriptHash` function) — auto-invalidates when the script changes, eliminates redundant disk reads

---

## Rationale

The PowerShell AST is syntax-aware. It correctly handles:
- Scriptblocks split across multiple lines
- Braces, `<#`, and `#>` inside string literals and heredocs
- `New-Step` and `Stop-Stepper` appearing inside comments (they simply won't produce `CommandAst` nodes)
- All PS quoting rules by construction

The alternative — keeping regex but fixing edge cases — is a local patch on a structural problem. Every edge case fixed reveals the next one.

---

## Consequences

- `Get-ScriptAst.ps1` added to `Private/`
- `Get-StepInventory.ps1` added to `Private/` — encapsulates the deduplicated step-counting logic
- `Find-NewStepBlocks.ps1` signature changes from `[object[]]$ScriptLines` to `[string]$ScriptPath`; brace-counting loop replaced with `$ast.FindAll(...)` + `Extent` properties
- `Find-UnmanagedCodeBlocks.ps1` comment detection replaced with token stream inspection; executable-line classification replaced with AST extent check
- `Test-StepperScriptRequirements.ps1` uses `$ast.ParamBlock.Attributes` and `$ast.ScriptRequirements.RequiredModules` instead of regex
- `New-Step.ps1` 3 duplicate step-counting blocks replaced with single `Get-StepInventory` calls; 9 regex lines removed
- **Line number convention:** AST uses 1-based line numbers; internal array indexing remains 0-based. Conversion happens at the boundary in `Find-NewStepBlocks` (subtract 1 when storing `Start`/`End`). This is documented in `Get-ScriptAst` help.
- Existing Pester suite must pass without modification after refactor. New edge-case tests added for multi-line syntax, `New-Step` in string literals, `New-Step` in comments.

---

## Rejected alternative

**Direct `[Parser]::ParseFile()` calls per function** — each function would handle its own `[ref]` vars and error handling. Rejected because:
- Error handling (`Write-Warning` per parse error) would be copy-pasted into 4–5 functions and drift over time
- The re-parsing problem (2–3 disk reads per execution) stays unfixed — caching can only be centralized in a wrapper
