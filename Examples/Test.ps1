[CmdletBinding()]
param()

Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

New-Step {
    $Stepper.AllProcesses = Get-Process
    $Stepper.ChildItems = Get-ChildItem
}

New-Step {
    $Stepper.AllProcesses | Select-Object -Last 3
}

New-Step {
    $Stepper.ChildItems| Select-Object -Last 3
}

Stop-Stepper
