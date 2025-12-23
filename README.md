# Stepper

A PowerShell module for creating resumable scripts with automatic state persistence.

## How It Works

- Each step is tracked by its location in the script (file:line)
- State is saved after each successful step in a `.stepper` file (includes `ScriptContents`, `LastCompletedStep`, timestamp, and persisted `$Stepper` data)
- On resume, completed steps are skipped automatically
- If the script has changed between runs, Stepper prompts the user to Resume, Start over (removes the state file), view More details, or Quit
- Non-resumable code is detected and can be suppressed with `# stepper:ignore` or handled interactively
- Use the More details view to inspect saved step body, Stepper variables, and restart context
- Call `Stop-Stepper` at the end to clean up

## Installation

```powershell
Install-Module -Name Stepper
```

## Usage

Wrap your script steps in `New-Step` blocks. If the script fails inside of a `New-Step` block, the next run of the script resumes at the step that failed.

```powershell
#Requires -Modules Stepper
[CmdletBinding()]
param()

New-Step {
    Write-Host "Step 1: Download files..."
    # Your code here
}

New-Step {
    Write-Host "Step 2: Process data..."
    # Your code here
}

New-Step {
    Write-Host "Step 3: Upload results..."
    # Your code here
}

Stop-Stepper
```
## Data Persistence

Use the `$Stepper` variable to share data between steps:

```powershell
New-Step {
    $Stepper.Data = Get-Process
}

New-Step {
    $Stepper.Data | Where-Object CPU -gt 100
}
```

## License

MIT with Commons Clause - see [LICENSE](LICENSE)
