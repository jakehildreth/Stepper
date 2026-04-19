# ADR 0002: Logging and Step Transcripts

**Date:** 2026-04-19
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

Stepper had no persistent log output. All status information was emitted via `Write-Verbose`, which is ephemeral — lost if the caller omits `-Verbose` or does not capture output. There was no record of step runtimes, step failures, or what happened during a previous run.

Three design questions required explicit decisions before implementation:

1. **Should logging be opt-in or opt-out?** Opt-in (e.g., requiring `-LogPath` on every step) is verbose and error-prone. Opt-out (logging on by default) is safer for unattended scripts.
2. **How should within-step command output be captured?** Stream redirection, verbose-only, or native PS transcripts.
3. **Where should the log file be stored?** Alongside the script, in a user-specified path, or somewhere else.

---

## Decision

### Logging is on by default; opt out with `-NoLog`

Logging is enabled for every step unless the user explicitly passes `-NoLog` to a `New-Step` call. When `-NoLog` is present on any step, Stepper prompts the user at init time to choose scope:

- **A** — log all steps (ignore `-NoLog` flags)
- **S** — skip logging for the flagged steps only
- **N** — disable logging entirely

This decision is persisted in the `.stepper` state file so resumed runs do not re-prompt.

Rationale: unattended scripts need logs most — requiring an explicit opt-in means logs are missing exactly when they're most needed.

### Native `Start-Transcript` per step, folded into the log file

Each step is wrapped with `Start-Transcript`/`Stop-Transcript` writing to a temp file. After the step completes (or fails), the transcript content is appended to the structured log file between `=== BEGIN STEP N TRANSCRIPT ===` / `=== END STEP N TRANSCRIPT ===` delimiters.

Rationale: `Start-Transcript` captures the full host output including `Write-Host` in both PS 5.1 and PS Core. Stream redirection (`6>&1 5>&1 ...`) does not capture `Write-Host` in PS 5.1 and produces interleaved `InformationRecord` objects rather than readable text.

### Active transcript detection is a hard stop

Before starting a per-step transcript, Stepper checks `$Host.UI.IsTranscribing`. If `$true`, it emits a clear user-facing message and throws a terminating error (`TranscriptAlreadyActive`, category `ResourceBusy`). It does not silently skip transcript capture and continue.

Rationale: silently skipping produces a log with missing transcript sections — worse than a clear failure because the user may not notice. A hard stop with an actionable message (`Stop-Transcript and re-run`) is unambiguous.

### Default log path: `scriptname.ps1.stepper.log` alongside the script

If no `-LogPath` is specified on any `New-Step` call, the log is written to the same directory as the script with the filename `<scriptname>.ps1.stepper.log`. This keeps all Stepper-owned files co-located and identifiable (`.stepper` state + `.stepper.log` log).

If one or more `New-Step` calls specify `-LogPath` with a static string, that path is used. If multiple calls specify different paths, Stepper prompts the user to choose (non-interactive default: first seen + `Write-Warning`). Dynamic paths (variables) cannot be resolved at AST-scan time; the first runtime value wins and a `Write-Warning` is emitted if a subsequent call provides a different value.

### Log config persisted in `.stepper` state file

`LogPath`, `LoggingEnabled`, and `NoLogStepIds` are added to the existing `Export-Clixml` state object. On a resumed run, these values are read from state and applied without re-prompting.

Rationale: consistency — the path and scope decisions made on the first run should apply to the resumed run, which may be unattended.

---

## Consequences

- **New private functions:** `Write-StepperLog` (structured log helper), `Get-StepLogConfig` (AST scan for `-LogPath` and `-NoLog` across all steps)
- **State schema change:** three new fields (`LogPath`, `LoggingEnabled`, `NoLogStepIds`) added to the `Export-Clixml` object in `Write-StepperState.ps1`. Backwards compatible — old state files simply lack these fields (treated as `$null`/`$false`).
- **`New-Step` new params:** `-LogPath [string]`, `-NoLog [switch]`
- **`Stop-Stepper` no new params:** reads `LogPath` from `__StepperExecutionState` in the calling scope; no user-facing change.
- **Temp files:** one temp file per step execution, deleted in a `finally` block. If the process is killed mid-step, the temp file may be orphaned in `$env:TEMP` — acceptable.
- **PS 5.1 + active transcript:** hard stop with `TranscriptAlreadyActive`. Users running enterprise runbooks that pre-start transcripts must stop them before using Stepper logging. `-NoLog` on all steps or `-N` at the scope prompt is the workaround.
- **`Read-Host` not captured in transcripts on Unix/macOS:** `Start-Transcript` on PS Core (Unix/macOS) does not capture `Read-Host` prompts or their responses. Pipeline output, `Write-Host`, and `Write-Output` are captured normally. This is a `Start-Transcript` platform limitation — not a Stepper defect. On Windows (PS 5.1 or PS 7), `Read-Host` prompts are captured.

---

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Opt-in logging via `-LogPath` on every step | Verbose, error-prone; logs missing in unattended scenarios |
| Stream redirection (`6>&1 5>&1 2>&1`) | Does not capture `Write-Host` in PS 5.1 |
| Separate transcript file per step | Adds file proliferation; structured log + sections is more readable |
| `Set-StepperConfig` module-level cmdlet | Adds a new public API for a problem already solved by per-step params + state persistence |
| Silent skip on active transcript | Produces silently incomplete logs; hard stop is safer and more honest |
