
New-Step {
    $Stepper.ProcessCount = (Get-Process).Count
    $Stepper.ItemCount = (Get-ChildItem).Count
}

Write-Host 'Non-resumable code between steps 1 and 2.'

New-Step {
    Write-Host "Running process count: $($Stepper.ProcessCount)"
}

New-Step {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Simulating crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Items in current folder count: $($Stepper.ItemCount)"
}

New-Step {
    $Stepper.ChildItems| Select-Object -Last 3
}

Stop-Stepper
