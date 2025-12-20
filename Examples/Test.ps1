
Write-Host 'Non-resumable code before first step.'
New-Step {
    $Stepper.AllProcesses = Get-Process
    $Stepper.ChildItems = Get-ChildItem
}

Write-Host 'Non-resumable code between steps 1 and 2.'

New-Step {
    $Stepper.AllProcesses | Select-Object -Last 3
}

Write-Host 'Non-resumable code between steps 2 and 3.'

New-Step {
    $Stepper.ChildItems| Select-Object -Last 3
}

Write-Host $Stepper.ChildItems[0]

Stop-Stepper
