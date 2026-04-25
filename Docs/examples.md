# Examples

## Complete Example

```powershell
[CmdletBinding()]
param()

#region Stepper ignore
# This runs every time — safe to leave outside New-Step
$outputDir = Join-Path $PSScriptRoot 'output'
#endregion Stepper ignore

New-Step 'Create Output Directory' {
    Write-Host "[$($Stepper.StepName)] Step $($Stepper.StepNumber)"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $Stepper.OutputDir = $outputDir
}

New-Step 'Download Data' {
    # Simulate a download
    Start-Sleep -Seconds 1
    $Stepper.Files = @('a.csv', 'b.csv', 'c.csv')
    Write-Host "Downloaded $($Stepper.Files.Count) files."
}

New-Step {
    # Unnamed step — backward-compatible syntax
    foreach ($file in $Stepper.Files) {
        Write-Host "Processing $file in $($Stepper.OutputDir)..."
    }
}

Stop-Stepper
```

