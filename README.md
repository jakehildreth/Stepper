![The Stepper logo features the word Stepper in a bold, stylized font with a set of stairs ascending diagonally to the right. The design conveys a sense of progress and upward movement, aligning with the tool's purpose of step-by-step automation. The background is plain, ensuring the logo remains the focal point. Font used: https://www.dafont.com/pix.font?fpp=200](Images/Stepper.png)

# Stepper

A cross-platform PowerShell utility module for creating resumable, step-by-step scripts with automatic state persistence.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
[![PSGallery](https://img.shields.io/powershellgallery/v/Stepper)](https://www.powershellgallery.com/packages/Stepper)
![License](https://img.shields.io/badge/license-MIT%20w%2FCommons%20Clause-green)

---

## Table of Contents

- [Stepper](#stepper)
  - [Table of Contents](#table-of-contents)
  - [Quick Start](#quick-start)
  - [Demo](#demo)
  - [How It Works](#how-it-works)
    - [a. First Run — Script Validation](#a-first-run--script-validation)
    - [b. Normal Execution](#b-normal-execution)
    - [c. Resume — Script Unchanged](#c-resume--script-unchanged)
    - [d. Resume — Script Modified](#d-resume--script-modified)
    - [e. More Details View](#e-more-details-view)
    - [f. Completion](#f-completion)
  - [Named Steps](#named-steps)
  - [Data Persistence](#data-persistence)
  - [Non-Resumable Code](#non-resumable-code)
  - [Non-Interactive Mode](#non-interactive-mode)
  - [Logo](#logo)
  - [Verbose Output](#verbose-output)
  - [State File](#state-file)
  - [Error Handling](#error-handling)
  - [API Reference](#api-reference)
    - [`New-Step`](#new-step)
    - [`Stop-Stepper`](#stop-stepper)
  - [Complete Example](#complete-example)
  - [Troubleshooting](#troubleshooting)
  - [License](#license)

---

## Quick Start

```powershell
Install-Module -Name Stepper -Scope CurrentUser -Force
```

Create a `.ps1` script with `New-Step` blocks:

```powershell
#Requires -Modules Stepper   # documents the dependency; Stepper enforces this
[CmdletBinding()]            # required for error propagation and -Verbose support
param()

New-Step 'Download Files' {
    Write-Host "Downloading files..."
    # your code here
}

New-Step 'Process Data' {
    Write-Host "Processing data..."
    # your code here
}

New-Step 'Upload Results' {
    Write-Host "Uploading results..."
    # your code here
}

Stop-Stepper   # removes the state file on successful completion
```

If the script fails inside a `New-Step` block, the next run resumes at the step that failed — all previously completed steps are skipped.

**Required declarations:** `[CmdletBinding()]` and `#Requires -Modules Stepper` must appear before the first `New-Step`. If they are missing, Stepper detects this on first run and prompts:

```
[A] Add declarations (default)
[S] Skip
[Q] Quit
```

Choosing `[A]` writes the declarations to the script and asks you to re-run.

---

## Demo

https://github.com/user-attachments/assets/4717179e-1698-4e19-aac3-e514d04333b8

Created with [VHS](https://github.com/charmbracelet/vhs) by [Charm](https://charm.land).

---

## How It Works

### a. First Run — Script Validation

Before executing any steps, Stepper validates the script:

1. Checks for `[CmdletBinding()]` and `#Requires -Modules Stepper` — prompts to add them if missing
2. Scans for non-resumable code between `New-Step` blocks — prompts per block: Wrap / Mark / Delete / Ignore
3. Checks that `Stop-Stepper` appears at the end

If the script is modified by any of the above, Stepper writes the changes and asks you to re-run.

### b. Normal Execution

- Each `New-Step` block is identified by `filepath:lineNumber`
- After each step succeeds, state is serialized to a `.stepper` file (XML via `Export-Clixml`) in the same directory as the script
- State includes: SHA256 hash, full script contents, last completed step, step name/number, timestamp (ISO 8601), and the full `$Stepper` hashtable

### c. Resume — Script Unchanged

On the next run, Stepper finds the `.stepper` file, computes the current SHA256, and if it matches prompts:

```
[R] Resume (default)   [S] Start over   [M] More details   [Q] Quit
```

Resume mode skips all steps up to and including `LastCompletedStep` and continues from the next one.

### d. Resume — Script Modified

If the hash doesn't match, Stepper warns about the inconsistency and prompts:

```
[R] Resume (risky)   [S] Start over   [M] More details   [Q] Quit
```

Start over removes the state file and runs fresh.

### e. More Details View

Selecting `[M]` shows:

- Script hash comparison (saved vs. current)
- Full `$Stepper` variable contents (JSON formatted)
- Last completed step name, number, and line
- Full source code of the last completed step (extracted via PowerShell AST, with brace-matching fallback)

### f. Completion

`Stop-Stepper` removes the `.stepper` file. The next run has no state and executes all steps from scratch.

---

## Named Steps

Steps can be given names for clearer resume prompts and verbose output.

```powershell
# positional (preferred)
New-Step 'Download Files' {
    Write-Host "Step: $($Stepper.StepName), number: $($Stepper.StepNumber)"
}

# explicit parameter
New-Step -Name 'Process Data' {
    Write-Host "Processing..."
}

# unnamed — backward-compatible, always works
New-Step {
    Write-Host "No name, no problem."
}
```

**Resume prompt display:**
- Named: `Download Files (Step 1, Line 12)`
- Unnamed: `Step 1 (Line 12)`

**Verbose output:**
- Named: `Executing step 1/3 - 'Download Files'`
- Unnamed: `Executing step 1/3`

**Available inside every block:**
- `$Stepper.StepName` — the name passed to `New-Step`, or `$null` if unnamed
- `$Stepper.StepNumber` — 1-based index of the current step

Both values are also persisted to the state file as `LastCompletedStepName` and `LastCompletedStepNumber`.

---

## Data Persistence

`$Stepper` is a hashtable initialized in the calling scope on the first `New-Step` invocation. Any key/value you add is automatically serialized to the `.stepper` file after each step and restored on resume.

```powershell
New-Step 'Gather Data' {
    $Stepper.Servers = Get-Content servers.txt
    $Stepper.StartTime = Get-Date
}

New-Step 'Process Data' {
    # $Stepper.Servers is available here even after a crash and resume
    foreach ($server in $Stepper.Servers) {
        Write-Host "Processing $server..."
    }
}

New-Step 'Report' {
    $elapsed = (Get-Date) - $Stepper.StartTime
    Write-Host "Finished in $($elapsed.TotalSeconds)s"
}

Stop-Stepper
```

**System-injected keys** (read-only by convention): `$Stepper.StepName`, `$Stepper.StepNumber`

`$Stepper` data persists until `Stop-Stepper` deletes the state file.

---

## Non-Resumable Code

Code outside `New-Step` blocks re-executes on every run. For long-running scripts this can mean duplicate API calls, redundant file downloads, or unintended side effects.

**What Stepper flags:**
- Code before the first `New-Step`
- Code between consecutive `New-Step` blocks
- Code between the last `New-Step` and `Stop-Stepper`

**What Stepper ignores** (safe to leave outside blocks):
- Empty lines and `#` comments
- Multi-line comment blocks (`<# ... #>`)
- Declarations: `[CmdletBinding()]`, `param()`, `using`
- Lines inside `#region Stepper ignore` / `#endregion Stepper ignore`

**Interactive resolution per block:**

```
[W] Wrap in New-Step (default)   [M] Mark as ignored   [D] Delete   [I] Ignore   [Q] Quit
```

**The `#region Stepper ignore` directive** — use this to mark code that must run every time but shouldn't be flagged:

```powershell
#region Stepper ignore
$logPath = Join-Path $PSScriptRoot 'output.log'
$ErrorActionPreference = 'Stop'
#endregion Stepper ignore
```

If a flagged block references `$Stepper.*` variables, Stepper warns before offering Delete.

---

## Non-Interactive Mode

When `Read-Host` is unavailable (CI/CD, remoting, unattended runs), Stepper falls back to safe defaults:

| Prompt | Default |
|---|---|
| Missing declarations | Add |
| Non-resumable code | Wrap |
| Resume — script unchanged | Resume |
| Resume — script modified | Start over |

---

## Logo

Stepper displays a colorful pixel-art logo on module import. To suppress it:

```powershell
$env:STEPPER_SHOW_LOGO = 'false'
```

---

## Verbose Output

Run your script with `-Verbose` to see timestamped activity from Stepper:

```
[2026-03-08 14:22:01][Stepper] Executing step 1/3 - 'Download Files'
[2026-03-08 14:22:03][Stepper] Step complete. Writing state...
[2026-03-08 14:22:03][Stepper] Executing step 2/3 - 'Process Data'
```

Verbose messages cover: step execution, state read/write/remove, variable changes, and hash comparisons. Requires `[CmdletBinding()]` in the calling script.

---

## State File

Stepper stores state in `<scriptname>.ps1.stepper` alongside the script, using PowerShell's `Export-Clixml` / `Import-Clixml` serialization format.

**Contents:**

| Field | Description |
|---|---|
| `ScriptHash` | SHA256 of the script at time of save |
| `ScriptContents` | Full script text (used by More Details view) |
| `LastCompletedStep` | `filepath:lineNumber` identifier |
| `LastCompletedStepName` | Step name, or `$null` if unnamed |
| `LastCompletedStepNumber` | 1-based step index |
| `Timestamp` | ISO 8601 datetime |
| `StepperData` | Serialized `$Stepper` hashtable |

**Manual inspection:**

```powershell
Import-Clixml .\myscript.ps1.stepper
```

**Cleanup:** `Stop-Stepper` deletes the file. Manual deletion is always safe — the next run simply starts fresh.

---

## Error Handling

- If a step throws, Stepper propagates a terminating error with step context (identifier, name, number). State is **not** saved for the failed step — on resume, that step re-executes.
- Stepper uses `$PSCmdlet.ThrowTerminatingError()` with properly typed `ErrorRecord` objects (category, exception, target) throughout.
- All file I/O errors are caught and surfaced as `ErrorRecord`s rather than raw exceptions.
- `[CmdletBinding()]` in the calling script is required for error propagation to work correctly.

---

## API Reference

### `New-Step`

Executes a step in a resumable script. Tracks state by `filepath:lineNumber`.

**Syntax:**

```powershell
New-Step [-Name] <string> [-ScriptBlock] <scriptblock>
New-Step [-ScriptBlock] <scriptblock>
```

**Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Name` | `string` | No | Display name shown in prompts and verbose output |
| `ScriptBlock` | `scriptblock` | Yes | The code to execute |

**Notes:** Must be called from a `.ps1` file. Does not work from the console or an unsaved editor buffer.

---

### `Stop-Stepper`

Removes the state file. Call at the end of every Stepper-enabled script.

**Syntax:**

```powershell
Stop-Stepper
```

**Notes:** Automatically locates the calling script's state file via the call stack.

---

## Complete Example

```powershell
#Requires -Modules Stepper
[CmdletBinding()]
param()

#region Stepper ignore
# This runs every time — safe to leave outside New-Step
$outputDir = Join-Path $PSScriptRoot 'output'
#endregion Stepper ignore

New-Step 'Create Output Directory' {
    Write-Host "[$($Stepper.StepName)] Step $($Stepper.StepNumber)"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $Stepper.OutputDir = $outputDir
}

New-Step 'Download Data' {
    # Simulate a download
    Start-Sleep -Seconds 1
    $Stepper.Files = @('a.csv', 'b.csv', 'c.csv')
    Write-Host "Downloaded $($Stepper.Files.Count) files."
}

New-Step {
    # Unnamed step — backward-compatible syntax
    foreach ($file in $Stepper.Files) {
        Write-Host "Processing $file in $($Stepper.OutputDir)..."
    }
}

Stop-Stepper
```

---

## Troubleshooting

**"Stepper says my script has changed"**
Script hash mismatch. Choose `[S] Start over` for a clean run, or `[R] Resume (risky)` if you're confident the change doesn't affect completed steps.

**"Stepper is prompting about non-resumable code"**
Code exists outside `New-Step` blocks. Wrap it in a `New-Step`, mark it with `#region Stepper ignore`, or delete it if it's dead code.

**"New-Step doesn't work from the console"**
Stepper uses the call stack to find the script file. It must be called from a saved `.ps1` file, not an interactive session.

**"The state file is stale / from a previous run I don't want"**
Delete the `.stepper` file manually, or select `[S] Start over` at the resume prompt.

**"The logo is distracting"**
Set `$env:STEPPER_SHOW_LOGO = 'false'` before importing the module.

---

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
