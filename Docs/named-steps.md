# Named Steps

Steps can be given names for clearer resume prompts and verbose output.

```powershell
New-Step 'Download Files' {
    # positional (preferred)
    Write-Host "Step: $($Stepper.StepName), number: $($Stepper.StepNumber)"
}

New-Step -Name 'Process Data' {
    # explicit parameter
    Write-Host "Processing..."
}

New-Step {
    # unnamed (backward-compatible, always works)
    Write-Host "No name, no problem."
}
```

## Display Formats

**Resume prompts:**
- Named: `Download Files (Step 1, Line 12)`
- Unnamed: `Step 1 (Line 12)`

**Verbose output:**
- Named: `[2026-03-08 14:22:01][INFO][Stepper] Executing step 1/3 - 'Download Files' (Script.ps1:6)`
- Unnamed: `[2026-03-08 14:22:01][INFO][Stepper] Executing step 1/3 (Script.ps1:6)`

## Step Metadata

Available inside every block:

- `$Stepper.StepName`: the name passed to `New-Step`, or `$null` if unnamed
- `$Stepper.StepNumber`: 1-based index of the current step

Both values are persisted to the state file as `LastCompletedStepName` and `LastCompletedStepNumber`.
