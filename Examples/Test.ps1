[CmdletBinding()]
param()

Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

New-Step {
    $Stepper.AllProcesses = Get-Process
    $Stepper.ChildItems = Get-ChildItem
}

Write-Host 'Non-resumable code between steps.'

New-Step {
    $Stepper.AllProcesses | Select-Object -Last 3
}

Write-Host 'Non-resumable code between steps.'

New-Step {
    $Stepper.ChildItems| Select-Object -Last 3
}

Write-Host $Stepper.ChildItems[0]

Stop-Stepper
