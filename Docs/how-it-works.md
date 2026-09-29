# How It Works

## Script Integrity Pipeline

Before Stepper creates or reads runtime state, `Start-Stepper` runs this pipeline:

1. `Test-StepperScript` parses the complete Stepper script and returns canonical findings.
2. Parse errors stop execution. Safe missing structure is added in one deterministic repair transaction.
3. Remaining structural Errors stop execution, except `NoSteps`, which is deferred until unmanaged code can be wrapped into the first `New-Step`.
4. Misplaced or duplicate Start calls are handled before unmanaged code.
5. Unmanaged code is handled with Wrap / Mark ignored / Delete / Ignore / Quit.
6. `NoSteps` is enforced, then missing `Stop-Stepper` is offered as Add / Continue / Quit.
7. Cross-step variable conversion is the final rewrite-capable phase.

A rewrite creates one backup, writes once, removes stale state, and exits with code `75`. Run the script again to continue. `$Stepper`, the script hash, step inventory, and saved state are not initialized until the pipeline finishes without a rewrite or unresolved Error.

## Normal Execution

- Each `New-Step` block is identified by `filepath:lineNumber`
- After each step succeeds, state is serialized to a `.stepper` file (XML via `Export-Clixml`) in the same directory as the script
- State includes: SHA256 hash, full script contents, last completed step, step name/number, timestamp (ISO 8601), and the full `$Stepper` hashtable

## Resume, Script Unchanged

On the next run, Stepper finds the `.stepper` file, computes the current SHA256, and if it matches prompts:

```
[R] Resume (default)   [s] Start over   [m] More details   [q] Quit
```

Resume mode skips all steps up to and including `LastCompletedStep` and continues from the next one.

## Resume, Script Modified

If the hash doesn't match, Stepper warns about the inconsistency and prompts:

```
[r] Resume (risky)   [S] Start over (default)   [m] More details   [q] Quit
```

Start over is a pristine fresh start: it removes the state file, clears the `$Stepper` variable from your session, and discards the previous run's logging choices (log path, logging on/off, and any `-NoLog` decisions), so the new run re-resolves logging from scratch. No data from the previous run carries over.

## More Details View

Selecting `[M]` shows:

- Script hash comparison (saved vs. current)
- Full `$Stepper` variable contents (JSON formatted)
- Last completed step name, number, and line
- Full source code of the last completed step (extracted via PowerShell AST, with brace-matching fallback)

## Completion

`Stop-Stepper` removes the `.stepper` file. The next run has no state and executes all steps from scratch.

## Non-Interactive Mode

When `Read-Host` is unavailable (CI/CD, remoting, unattended runs), Stepper falls back to safe defaults:

| Situation | Behavior |
|---|---|
| Missing required structure | Repair, remove stale state, exit `75` |
| Misplaced or duplicate Start call | Fail without rewriting |
| Unmanaged code | Wrap, remove stale state, exit `75` |
| Unresolved `NoSteps` | Fail |
| Missing `Stop-Stepper` | Warn and continue |
| Cross-step variable candidates | Fail and require interactive review |
| Resume, script unchanged | Resume |
| Resume, script modified | Start over |
| Malformed or inconsistent state | Fail |

## Migration and Compatibility

`Start-Stepper` now owns validation, repair orchestration, conversion review, and runtime-state initialization. `New-Step` only executes managed step blocks and requires successful initialization first.

Existing scripts can keep passing `-SkipRequirementsCheck` to `Start-Stepper` or `New-Step`; the hidden parameter remains accepted for compatibility but is now a no-op. The integrity pipeline cannot be bypassed. Scripts that previously relied on silent first-step injection should expect an early backup and exit code `75`, then rerun from the rewritten source.

Because rewrite exits must stop the script without terminating the caller's interactive session, invoke Stepper scripts with `& ./Script.ps1` or `./Script.ps1`, not dot-sourcing.

## Verbose Output

Run your script with `-Verbose` to see timestamped activity from Stepper:

```
[2026-03-08 14:22:01][Stepper] Executing step 1/3 - 'Download Files'
[2026-03-08 14:22:03][Stepper] Step complete. Writing state...
[2026-03-08 14:22:03][Stepper] Executing step 2/3 - 'Process Data'
```

Verbose messages cover: step execution, state read/write/remove, variable changes, and hash comparisons. Requires `[CmdletBinding()]` in the calling script.

## Logging

Stepper writes a structured log file (`<scriptname>.ps1.stepper.log`) alongside the script by default. Each step produces:

- An `[INFO]` entry at the start of execution with step number and source location
- A per-step transcript section (`=== BEGIN STEP N TRANSCRIPT ===`) capturing host output
- An `[INFO]` entry on completion with elapsed time
- An `[ERROR]` entry if the step fails

Logging is on by default. Use `-NoLog` on a `New-Step` call to exclude a step, or `-LogPath` to override the log file location. See [Logging](logging.md) for full details.

## Logo

Stepper displays a colorful pixel-art logo on module import. To suppress it:

```powershell
$env:STEPPER_SHOW_LOGO = 'false'
```
