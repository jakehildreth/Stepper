# Unmanaged Code

Code outside `New-Step` blocks re-executes on every run. For long-running scripts this can mean duplicate API calls, redundant file downloads, or unintended side effects.

## What Stepper Flags

- Code before the first `New-Step`
- Code between consecutive `New-Step` blocks
- Code between the last `New-Step` and `Stop-Stepper`

## What Stepper Ignores

The following are always safe outside blocks:

- Empty lines and `#` comments
- Multi-line comment blocks (`<# ... #>`)
- Declarations: `[CmdletBinding()]`, `param()`, `using`
- Lines inside `#region Stepper ignore` / `#endregion Stepper ignore`

## Interactive Resolution

For each flagged block, Stepper prompts:

```
[W] Wrap in New-Step block (default)   [m] Mark as expected to ignore   [d] Delete this code   [i] Ignore and continue   [q] Quit
```

## The `#region Stepper ignore` Directive

Use this to mark code that must run every time but shouldn't be flagged:

```powershell
#region Stepper ignore
$logPath = Join-Path $PSScriptRoot 'output.log'
$ErrorActionPreference = 'Stop'
#endregion Stepper ignore
```

If a flagged block references `$Stepper.*` variables, Stepper warns before offering Delete.
