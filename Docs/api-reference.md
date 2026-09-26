# API Reference

## `Start-Stepper`

Validates and initializes a Stepper script before any managed code or runtime state is used. Alias: `Initialize-Stepper`.

```powershell
Start-Stepper
```

`Start-Stepper` runs the canonical integrity pipeline, coordinates approved remediation, completes cross-step conversion review, and only then initializes resume state and `$Stepper`. Source rewrites create a backup, remove stale state, and exit with code `75`. Scripts must be invoked normally; dot-sourcing is rejected because Stepper must be able to stop safely after a rewrite.

In non-interactive hosts, deterministic repairs and unmanaged-code wrapping are automatic; lifecycle conflicts, unresolved `NoSteps`, conversion candidates, and malformed state fail safely. Matching state resumes, while a script-hash mismatch starts over.

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | The user cancelled via Quit. No changes were made. |
| `1` | Validation failure: parse errors, unresolved deterministic errors, or unresolved `NoSteps`. |
| `75` | The source was rewritten (backup created, stale state removed). Run the script again. |

## `New-Step`

Executes a step in a resumable script. Tracks state by `filepath:lineNumber`.

```powershell
New-Step [-Name] <string> [-ScriptBlock] <scriptblock> [-LogPath <string>] [-NoLog] [-Retry] [-RetryInterval <int>] [-MaxRetries <int>]
New-Step [-ScriptBlock] <scriptblock> [-LogPath <string>] [-NoLog] [-Retry] [-RetryInterval <int>] [-MaxRetries <int>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Name` | `string` | No | Display name shown in prompts and verbose output |
| `ScriptBlock` | `scriptblock` | Yes | The code to execute |
| `LogPath` | `string` | No | Path to the log file. Overrides the default (`<scriptname>.ps1.stepper.log`). Only needs to be specified once. Stepper resolves it via AST scan at init time. |
| `NoLog` | `switch` | No | Exclude this step from logging. At init time Stepper prompts to choose scope: log all / skip flagged / disable entirely. |
| `Retry` | `switch` | No | Enable exponential backoff retry for this step. |
| `RetryInterval` | `int` | No | Base interval in seconds between retries. Each attempt waits `RetryInterval * 2^attempt` seconds. Default: `60`. Minimum: `1`. Has no effect without `-Retry` (a warning is emitted and execution continues). |
| `MaxRetries` | `int` | No | Max retry attempts after the initial failure (so up to `MaxRetries + 1` total executions). Default: `5`. Minimum: `1`. Has no effect without `-Retry` (a warning is emitted and execution continues). |

Must be called from a saved `.ps1` file. Does not work from the console or an unsaved editor buffer.

`New-Step` performs no initialization. If `Start-Stepper` has not run first, it throws a terminating `StartStepperNotRun` error telling you to add `Start-Stepper` inside the first `#region Stepper ignore` block. The hidden `-SkipRequirementsCheck` switch is still accepted for backward compatibility but is a no-op.

See [Logging](logging.md) for full details on log format, step transcripts, and active transcript conflict handling.

### Retry Behavior

When `-Retry` is specified, the `ScriptBlock` runs inside an exponential backoff loop:
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

Automatically locates the calling script's state file via the call stack. If the call stack yields no script path, it falls back to the `CurrentScriptPath` recorded in `__StepperExecutionState` during `Start-Stepper`.

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

Supports `-WhatIf` and `-Confirm` (SupportsShouldProcess, ConfirmImpact `Low`).

Both the minimal and showcase templates pass `Test-StepperScript` with `IsValid = $true` out of the box.

## `Test-StepperScript`

Validates a script file against Stepper conventions without modifying it.

```powershell
Test-StepperScript [-ScriptPath] <string>
Test-StepperScript [-Path] <string>   # alias
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ScriptPath` | `string` | Yes | Path to the `.ps1` file to inspect. Relative paths are resolved. Also accepts `-Path` |

Returns a `PSCustomObject` with:

| Property | Type | Description |
|---|---|---|
| `Path` | `string` | Resolved path to the script |
| `IsValid` | `bool` | `$true` when no Error-severity issues exist |
| `Issues` | `PSCustomObject[]` | Array of `{ Code, Severity, Message, Location, Remediation }` findings |

`Location` contains start/end line and column data plus the offending source text when a source extent exists. `Remediation` is `Deterministic`, `Interactive`, or `None`.

Error codes:

`NotStepperScript`, `ParseError`, `MissingParamBlock`, `MissingCmdletBinding`, `MissingInstallGuard`, `InvalidInstallGuard`, `MisplacedInstallGuard`, `MissingBootstrapRegion`, `MalformedIgnoreRegion`, `MissingStartStepper`, `DuplicateStartStepper`, `NestedStartStepper`, `StartOutsideBootstrapRegion`, `StartBeforeInstallGuard`, `StartAfterExecutableCode`, `NoSteps`, `NestedNewStep`, `MissingStepScriptBlock`, `NewStepBeforeStart`, `NewStepAfterStop`, `DuplicateStopStepper`, `NestedStopStepper`, `ExecutableCodeAfterStop`, and `UnmanagedCode`.

Warning codes:

- `MissingStopStepper`

`IsValid` is `$true` when zero Error findings are present. Warnings are informational and do not affect validity.

## `Repair-StepperScript`

Applies safe deterministic additions required by a Stepper script.

```powershell
Repair-StepperScript [-ScriptPath] <string> [-WhatIf]
Repair-StepperScript [-Path] <string> [-WhatIf]   # alias
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ScriptPath` | `string` | Yes | Path to the `.ps1` file to repair. Relative paths are resolved. Also accepts `-Path` |

Fixes applied automatically:

| Issue code | Fix |
|---|---|
| `MissingParamBlock` | Inserts a `[CmdletBinding()]` param block at the legal script-header position |
| `MissingCmdletBinding` | Adds `[CmdletBinding()]` to the existing param block |
| `MissingInstallGuard` | Adds the canonical install guard and Stepper-ignore region after `param()` |
| `MissingBootstrapRegion` | Wraps an already-canonical install guard in a Stepper-ignore region |
| `MissingStartStepper` | Adds `Start-Stepper` immediately after a canonical guarded install |

Warnings are never repaired automatically. Unsafe insertion
points are left unchanged and remain in `Issues`.

Returns `{ Path, IsValid, Issues, Changed, BackupPath, AppliedRepairs,
PlannedRepairs }`. A real repair creates one backup, performs one write, removes
stale Stepper state, and returns fresh post-write findings. `-WhatIf` returns the
current findings and planned repairs without creating a backup, writing the script,
removing state, or performing a post-write test. Supports `-WhatIf` and `-Confirm`
(SupportsShouldProcess, ConfirmImpact `Medium`).

## `ConvertTo-StepperScript`

Detects variables that cross step boundaries and rewrites them to `$Stepper.<Var>` notation so they persist across steps and resume correctly after a crash.

The conversion sentinel (`$StepperConversionComplete`) records that the review is complete so the script-integrity lifecycle does not offer it again. The command can also be run manually.

```powershell
ConvertTo-StepperScript [-Path] <string> [-OutputPath <string>] [-Force] [-WhatIf]
ConvertTo-StepperScript -Name <string> [-Directory <string>] [-OutputPath <string>] [-Force] [-WhatIf]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Path` | `string` | Yes (ByPath) | Path to the `.ps1` file to convert. Also accepts the alias `-ScriptPath` |
| `Name` | `string` | Yes (ByName) | Script name with or without `.ps1`. Used with `-Directory` |
| `Directory` | `string` | No | Directory for `-Name` mode. Defaults to `$PWD` |
| `OutputPath` | `string` | No | Write converted content here instead of modifying the source. No backup is created when set |
| `Force` | `switch` | No | Explicitly convert all candidates without per-variable confirmation |

**Variable detection rules.** A variable is a candidate if it is:

1. Assigned in one `New-Step` block and read in a later block
2. Assigned in unmanaged (script-level) code and read inside any step
3. Both assigned and read inside the same `-Retry` step (local variables reset on every retry attempt)

When candidates are found, ConvertTo prompts for each:

```
[Y] Yes (default)   [n] No, skip   [a] All, convert remaining   [q] Quit
```

Completing the review writes `$StepperConversionComplete = $true` inside `#region Stepper ignore`, including when every candidate is declined. Choosing Quit writes nothing. If candidates exist but interactive input is unavailable, conversion fails with an actionable error instead of converting or skipping candidates. When candidates are converted and the script does not contain a `Start-Stepper` (or `Initialize-Stepper`) call, one is inserted automatically at the canonical position.

An in-place review creates one collision-resistant timestamped backup (`<BaseName>.<yyyy.M.dHHmmssfff>[.<n>].ps1.bak`), performs one rewrite, and removes stale `.stepper` state. The returned result has `Status = 'RerunRequired'` and `RerunRequired = $true`, allowing the caller to stop before runtime-state handling and request a rerun. With `-OutputPath` the converted content is written there instead (no backup) and the result has `Status = 'WrittenToOutput'`. If the write is declined via `-WhatIf` or `-Confirm`, the result has `Status = 'Skipped'`. Quit and no-candidate outcomes return `RerunRequired = $false`; scripts with no candidates are not rewritten.

Supports `-WhatIf` and `-Confirm` (SupportsShouldProcess, ConfirmImpact `Medium`).

## Error Handling

- If a step throws, Stepper propagates a terminating error with the message `Step failed [<throw-site file:line>]: <message>`, ErrorId `StepExecutionFailed`, and the step identifier (`filepath:lineNumber`) as TargetObject. State is **not** saved for the failed step. On resume, that step re-executes.
- `[CmdletBinding()]` in the calling script is required for error propagation to work correctly. `Start-Stepper` adds it during deterministic repair, then exits with code `75` before managed code runs (see [How It Works](how-it-works.md)).
- All file I/O errors are surfaced as typed `ErrorRecord` objects, not raw exceptions.
