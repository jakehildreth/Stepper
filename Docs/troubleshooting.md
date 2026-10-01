# Troubleshooting

**Stepper fails with `StartStepperNotRun` ("Start-Stepper has not run for ...")**

`New-Step` was called without `Start-Stepper` initializing the run first. This is the most common breakage for scripts written before `Start-Stepper` existed. Fix: add the canonical bootstrap block at the top of the script, after `param()`:

```powershell
#region Stepper ignore
if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }
Start-Stepper
#endregion Stepper ignore
```

**Stepper exits with code 75**

Stepper changed the Stepper script successfully, but did not run its managed code. A backup was created and stale state was removed. Run the script again.

**My existing script now exits before the first step**

`Start-Stepper` now owns the complete integrity lifecycle. If it safely repairs missing structure or wraps unmanaged code, it backs up the script, removes stale state, and exits with code `75`. Rerun the script. The legacy `-SkipRequirementsCheck` switch is still accepted but no longer bypasses validation.

**Stepper reports a script-integrity finding**

Run `Test-StepperScript -Path ./YourScript.ps1` to view the finding code, severity, source location, and permitted repair type. `Repair-StepperScript` can add safe missing structure; other findings need an interactive decision or a manual edit.

**Stepper says my script has changed**

Script hash mismatch. Choose `[S] Start over` for a clean run, or `[R] Resume (risky)` if you're confident the change doesn't affect completed steps.

**Stepper is prompting about unmanaged code**

Code exists outside `New-Step` blocks. Wrap it in a `New-Step`, mark it with `#region Stepper ignore`, or delete it if it's dead code.

**New-Step doesn't work from the console**

Stepper uses the call stack to find the script file. It must be called from a saved `.ps1` file, not an interactive session.

**A dot-sourced Stepper script is rejected**

Run the saved script with `& ./YourScript.ps1` instead of `. ./YourScript.ps1`. Stepper must be able to stop the script safely after a source rewrite without closing the interactive PowerShell host.

**The state file is stale / from a previous run I don't want**

Delete the `.stepper` file manually, or select `[S] Start over` at the resume prompt.

**The logo is distracting**

Create `config.json` in the Stepper config directory (`$env:XDG_CONFIG_HOME/stepper/`, or `~/.config/stepper/` on Linux/macOS and `$env:APPDATA\stepper\` on Windows when `XDG_CONFIG_HOME` is not set) with:

```json
{
    "ShowLogo": false
}
```

**Stepper fails with `TranscriptAlreadyActive`**

A PowerShell transcript is already running (e.g., started in `$PROFILE` or by an enterprise runbook). Call `Stop-Transcript` before running the script, or add `-NoLog` to your steps and choose `[s]` or `[d]` at the scope prompt. `-NoLog` alone is not enough: the default `[A]` ignores the flags and the check still throws. See [Logging](logging.md) for details.

**`Read-Host` prompts and responses don't appear in the log file**

`Start-Transcript` on macOS/Linux (PS Core) does not capture `Read-Host` input. This is a platform limitation; all other output (`Write-Host`, pipeline, etc.) is captured normally. On Windows the behavior is the same in both PS 5.1 and PS 7.
