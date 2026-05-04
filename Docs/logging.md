# Logging

Stepper logs step execution to a structured log file by default. No configuration required.

---

## Log File Location

The log file is created alongside the script using the filename `<scriptname>.ps1.stepper.log`:

```
myscript.ps1
myscript.ps1.stepper
myscript.ps1.stepper.log
```

To write to a custom path, pass `-LogPath` on any `New-Step` call:

```powershell
New-Step 'Install Packages' -LogPath 'C:\Logs\deploy.log' {
    ...
}
```

You only need to specify `-LogPath` once in the script. Stepper uses the first value found via AST scan and applies it to all steps. If multiple steps specify **different** `-LogPath` values, Stepper prompts at init time to choose one. Dynamic paths (variables or expressions) cannot be resolved at scan time; the first runtime value wins and a warning is emitted if a later step provides a different one.

If the directory for the specified `-LogPath` does not exist, Stepper throws a terminating error before executing any steps.

---

## Disabling Logging

To disable logging for a specific step, add `-NoLog`:

```powershell
New-Step 'Handle Credentials' -NoLog {
    ...
}
```

When `-NoLog` is present on any step, Stepper prompts at init time:

```
One or more steps have -NoLog. How should logging be scoped?
[A] Log all steps (default)   [s] Skip only flagged steps   [d] Disable entirely   [q] Quit
```

| Choice | Behavior |
|---|---|
| `[A]` | Log all steps, ignore `-NoLog` flags (default) |
| `[s]` | Skip transcript/log for flagged steps only |
| `[d]` | Disable logging entirely for this run |
| `[q]` | Exit without running |

In non-interactive mode (CI/CD, remoting), the default is `[A]`.

---

## Log Format

Each entry uses the format:

```
[timestamp][LEVEL][Stepper] message
```

Example output:

```
[2026-04-19 07:52:10][INFO][Stepper] Executing step 1/3 (Test.ps1:6)
[2026-04-19 07:52:12][INFO][Stepper] Step 1/3 completed in 2.05s (Test.ps1:6)
[2026-04-19 07:52:12][INFO][Stepper] Executing step 2/3 (Test.ps1:19)
[2026-04-19 07:53:30][INFO][Stepper] Step 2/3 completed in 5.74s (Test.ps1:19)
[2026-04-19 07:53:30][INFO][Stepper] All steps complete. State file removed.
```

Levels: `INFO`, `WARN`, `ERROR`.

---

## Step Transcripts

Each step's host output is captured via `Start-Transcript` and appended to the log file between section delimiters:

```
=== BEGIN STEP 2 TRANSCRIPT ===
**********************
PowerShell transcript start
...
**********************
Hey, Jake!
There are 517 processes currently running.
**********************
PowerShell transcript end
...
**********************

=== END STEP 2 TRANSCRIPT ===
```

If a step fails mid-execution, the section is marked `[PARTIAL]`:

```
=== BEGIN STEP 2 TRANSCRIPT [PARTIAL] ===
...partial output...
=== END STEP 2 TRANSCRIPT [PARTIAL] ===
```

### Read-Host limitation on Unix/macOS

`Start-Transcript` on PS Core (macOS/Linux) does not capture `Read-Host` prompts or the user's responses. All other output (`Write-Host`, `Write-Output`, pipeline output) is captured normally.

On Windows with PS 5.1 or PS 7, `Read-Host` prompts and responses are included in the transcript.

---

## Active Transcript Conflict

Stepper checks `$Host.UI.IsTranscribing` before starting a per-step transcript. If a transcript is already active (e.g., started by an enterprise runbook or `$PROFILE`), Stepper throws:

```
TranscriptAlreadyActive: a PowerShell transcript is already running.
Stop-Transcript before running a Stepper script with logging enabled.
```

**Workarounds:**
- Call `Stop-Transcript` before running the script
- Add `-NoLog` to all steps
- Choose `[N]` (disable entirely) at the scope prompt

---

## Log Config Persistence

Logging configuration (`LogPath`, `LoggingEnabled`, `NoLogStepIds`) is stored in the `.stepper` state file. Resumed runs restore the same config without re-prompting.

See [Data Persistence](data-persistence.md) for the full state schema.
