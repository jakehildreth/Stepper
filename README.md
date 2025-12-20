# Stepper

A PowerShell module for creating resumable scripts with automatic state persistence.

## Installation

```powershell
Install-Module -Name Stepper
```

## Usage

Wrap your script steps in `New-Step` blocks. If the script fails, the next run resumes from the last completed step.

```powershell
#Requires -Modules Stepper

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

## How It Works

- Each step is tracked by its location in the script (file:line)
- State is saved after each successful step in a `.stepper` file
- On resume, completed steps are skipped automatically
- Script changes invalidate the state file
- Call `Stop-Stepper` at the end to clean up

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
