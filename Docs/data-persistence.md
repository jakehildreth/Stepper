# Data Persistence

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

## State File

Stepper stores state in `<scriptname>.ps1.stepper` alongside the script, using PowerShell's `Export-Clixml` / `Import-Clixml` serialization format.

| Field | Description |
|---|---|
| `ScriptHash` | SHA256 of the script at time of save |
| `ScriptContents` | Full script text (used by More Details view) |
| `LastCompletedStep` | `filepath:lineNumber` identifier |
| `LastCompletedStepName` | Step name, or `$null` if unnamed |
| `LastCompletedStepNumber` | 1-based step index |
| `Timestamp` | ISO 8601 datetime |
| `StepperData` | Serialized `$Stepper` hashtable |
| `LogPath` | Resolved path to the log file, or `$null` if logging is disabled |
| `LoggingEnabled` | `$true` unless the user chose `[d]` at the scope prompt |
| `NoLogStepIds` | Array of `filepath:lineNumber` identifiers for steps with `-NoLog` |

**Manual inspection:**

```powershell
Import-Clixml .\myscript.ps1.stepper
```

Manual deletion is always safe; the next run simply starts fresh.
