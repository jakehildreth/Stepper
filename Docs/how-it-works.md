# How It Works

## First Run — Script Validation

Before executing any steps, Stepper validates the script:

1. Checks for `[CmdletBinding()]` — if missing, silently injects `[CmdletBinding()]`, `param()`, and a self-install guard, then exits and asks you to re-run. No prompt, no `#Requires` statement added.
2. Scans for unmanaged code between `New-Step` blocks — prompts per block: Wrap / Mark / Delete / Ignore
3. Checks that `Stop-Stepper` appears at the end

If the script is modified by any of the above, Stepper writes the changes and asks you to re-run.

## Normal Execution

- Each `New-Step` block is identified by `filepath:lineNumber`
- After each step succeeds, state is serialized to a `.stepper` file (XML via `Export-Clixml`) in the same directory as the script
- State includes: SHA256 hash, full script contents, last completed step, step name/number, timestamp (ISO 8601), and the full `$Stepper` hashtable

## Resume — Script Unchanged

On the next run, Stepper finds the `.stepper` file, computes the current SHA256, and if it matches prompts:

```
[R] Resume (default)   [S] Start over   [M] More details   [Q] Quit
```

Resume mode skips all steps up to and including `LastCompletedStep` and continues from the next one.

## Resume — Script Modified

If the hash doesn't match, Stepper warns about the inconsistency and prompts:

```
[R] Resume (risky)   [S] Start over   [M] More details   [Q] Quit
```

Start over removes the state file and runs fresh.

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

| Prompt | Default |
|---|---|
| Missing `[CmdletBinding()]` | Silent auto-inject (always; no prompt) |
| Unmanaged code | Wrap |
| Resume — script unchanged | Resume |
| Resume — script modified | Start over |

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
