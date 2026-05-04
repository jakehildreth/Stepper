# API Reference

## `New-Step`

Executes a step in a resumable script. Tracks state by `filepath:lineNumber`.

```powershell
New-Step [-Name] <string> [-ScriptBlock] <scriptblock> [-LogPath <string>] [-NoLog] [-Retry] [-RetryInterval <int>] [-MaxRetries <int>] [-SkipRequirementsCheck]
New-Step [-ScriptBlock] <scriptblock> [-LogPath <string>] [-NoLog] [-Retry] [-RetryInterval <int>] [-MaxRetries <int>] [-SkipRequirementsCheck]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Name` | `string` | No | Display name shown in prompts and verbose output |
| `ScriptBlock` | `scriptblock` | Yes | The code to execute |
| `LogPath` | `string` | No | Path to the log file. Overrides the default (`<scriptname>.ps1.stepper.log`). Only needs to be specified once. Stepper resolves it via AST scan at init time. |
| `NoLog` | `switch` | No | Exclude this step from logging. At init time Stepper prompts to choose scope: log all / skip flagged / disable entirely. |
| `Retry` | `switch` | No | Enable exponential backoff retry for this step. |
| `RetryInterval` | `int` | No | Base interval in seconds between retries. Each attempt waits `RetryInterval * 2^attempt` seconds. Default: `60`. Minimum: `1`. Requires `-Retry`. |
| `MaxRetries` | `int` | No | Max retry attempts after the initial failure (so up to `MaxRetries + 1` total executions). Default: `5`. Minimum: `1`. Requires `-Retry`. |
| `SkipRequirementsCheck` | `switch` | No | Suppresses the automatic `[CmdletBinding()]` check and silent auto-inject. Use when you intentionally manage declarations yourself. |

Must be called from a saved `.ps1` file. Does not work from the console or an unsaved editor buffer.

See [Logging](logging.md) for full details on log format, step transcripts, and active transcript conflict handling.

### Retry Behavior

When `-Retry` is specified, the `ScriptBlock` runs inside an exponential backoff loop:
v
- On each failure, Stepper waits `RetryInterval * 2^attempt` seconds and retries
- The loop continues until the block succeeds or `MaxRetries` is exhausted
- If all attempts fail, Stepper propagates a terminating error and stops

**Important: local variables reset on every execution.** The `ScriptBlock` is re-invoked from scratch on each retry, so any local variable you assign is re-initialized on the next attempt. Use `$Stepper.*` keys to accumulate state across retries:

```powershell
New-Step 'Call API' -Retry -RetryInterval 5 -MaxRetries 4 {
    if ($null -eq $Stepper.RetryCount) { $Stepper.RetryCount = 0 }
    $Stepper.RetryCount++
    Write-Host "Attempt $($Stepper.RetryCount)..."
    Invoke-RestMethod https://api.example.com/data
}
```

`$Stepper.RetryCount` persists because it is stored in the `$Stepper` hashtable, which is serialized to the state file and restored between attempts.

## `Stop-Stepper`

Removes the state file. Call at the end of every Stepper-enabled script.

```powershell
Stop-Stepper
```

Automatically locates the calling script's state file via the call stack.

## `New-StepperScript`

Creates a new `.ps1` file pre-wired for Stepper use.

```powershell
New-StepperScript [-Path] <string> [-Force] [-Showcase]
New-StepperScript [-Name] <string> [-Directory <string>] [-Force] [-Showcase]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Path` | `string` | Yes (ByPath) | Full path to the `.ps1` file to create |
| `Name` | `string` | Yes (ByName) | Script name without extension. File is written as `<Name>.ps1` |
| `Directory` | `string` | No | Directory for `-Name` mode. Defaults to `$PWD` |
| `Force` | `switch` | No | Overwrite if the target file already exists |
| `Showcase` | `switch` | No | Generate the full feature-showcase template (aliases: `-Full`, `-Detailed`, `-WithExamples`) |

Returns `[System.IO.FileInfo]`: the created file, suitable for pipeline use.

Both the minimal and showcase templates pass `Test-StepperScript` with `IsValid = $true` out of the box.

## `Test-StepperScript`

Validates a script file against Stepper conventions without modifying it.

```powershell
Test-StepperScript [-ScriptPath] <string>
Test-StepperScript [-Path] <string>   # alias
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ScriptPath` | `string` | Yes | Absolute path to the `.ps1` file to inspect. Also accepts `-Path` |

Returns a `PSCustomObject` with:

| Property | Type | Description |
|---|---|---|
| `Path` | `string` | Resolved path to the script |
| `IsValid` | `bool` | `$true` when no Error-severity issues exist |
| `Issues` | `PSCustomObject[]` | Array of `{ Code, Severity, Message }` objects |

Issue codes:

| Code | Severity | Meaning |
|---|---|---|
| `MissingCmdletBinding` | Error | `[CmdletBinding()]` not present |
| `MissingInstallGuard` | Error | `Install-Module Stepper` guard absent |
| `MissingCbh` | Warning | No comment-based help block |
| `MissingStopStepper` | Warning | `Stop-Stepper` not called |
| `NoSteps` | Warning | No `New-Step` blocks found |

`IsValid` is `$true` when zero Error-severity issues are present. Warnings are informational and do not affect validity.

## `Repair-StepperScript`

Inspects a script for Stepper convention issues and silently fixes what it can.

```powershell
Repair-StepperScript [-ScriptPath] <string> [-WhatIf]
Repair-StepperScript [-Path] <string> [-WhatIf]   # alias
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ScriptPath` | `string` | Yes | Absolute path to the `.ps1` file to repair. Also accepts `-Path` |

Fixes applied automatically:

| Issue code | Fix |
|---|---|
| `MissingCmdletBinding` | Inserts `[CmdletBinding()] param()` |
| `MissingInstallGuard` | Inserts Install-Module guard after `param()` |
| `MissingCbh` | Delegates to `Add-StepperCbh` (silent) |

The following are reported via `Write-Warning` but **not** automatically fixed (require author decision):

- `MissingStopStepper`: placement depends on script structure
- `NoSteps`: may be intentional during authoring

Returns the post-fix result of `Test-StepperScript`. If no changes were needed, the script file is not modified. Supports `-WhatIf`.

## `ConvertTo-StepperScript`

Detects variables that cross step boundaries and rewrites them to `$Stepper.<Var>` notation so they persist across steps and resume correctly after a crash.

Called automatically on first run via `New-Step` when the conversion sentinel (`$StepperConversionComplete`) is absent. Can also be run manually at any time.

```powershell
ConvertTo-StepperScript [-Path] <string> [-OutputPath <string>] [-Force] [-WhatIf]
ConvertTo-StepperScript -Name <string> [-Directory <string>] [-OutputPath <string>] [-Force] [-WhatIf]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Path` | `string` | Yes (ByPath) | Path to the `.ps1` file to convert |
| `Name` | `string` | Yes (ByName) | Script name with or without `.ps1`. Used with `-Directory` |
| `Directory` | `string` | No | Directory for `-Name` mode. Defaults to `$PWD` |
| `OutputPath` | `string` | No | Write converted content here instead of modifying the source. No backup is created when set |
| `Force` | `switch` | No | Skip per-variable confirmation and convert all candidates |

**Variable detection rules.** A variable is a candidate if it is:

1. Assigned in one `New-Step` block and read in a later block
2. Assigned in unmanaged (script-level) code and read inside any step
3. Both assigned and read inside the same `-Retry` step (local variables reset on every retry attempt)

When candidates are found, ConvertTo prompts for each:

```
[Y] Yes (default)   [n] No, skip   [a] All, convert remaining   [q] Quit
```

On completion, `$StepperConversionComplete = $true` is injected inside `#region Stepper ignore`. `New-Step` checks for this sentinel and skips the conversion hook on all subsequent runs.

A timestamped backup (`<BaseName>.<yyyy.M.dHHmm>.ps1.bak`) is created alongside the script before any write.

## Error Handling

- If a step throws, Stepper propagates a terminating error with step context (identifier, name, number). State is **not** saved for the failed step. On resume, that step re-executes.
- `[CmdletBinding()]` in the calling script is required for error propagation to work correctly. Stepper auto-injects it if missing (see [How It Works](how-it-works.md)).
- All file I/O errors are surfaced as typed `ErrorRecord` objects, not raw exceptions.
