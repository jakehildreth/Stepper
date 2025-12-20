Write-Host 'Non-resumable code before the first step.'

New-Step {
    $Stepper.ProcessCount = (Get-Process).Count
    $Stepper.ItemCount = (Get-ChildItem).Count
}

Write-Host "Running process count: $($Stepper.ProcessCount)"

New-Step {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Simulating crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Items in current folder count: $($Stepper.ItemCount)"
}

Write-Host 'Non-resumable code between last step and Stop-Stepper'
$Stepper.ChildItems | Select-Object -Last 3
Write-Host 'Because it references $Stepper.Variables, it should not be moved'
Write-Host 'after Stop-Stepper'


Stop-Stepper
