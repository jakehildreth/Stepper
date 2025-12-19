[CmdletBinding()]
param()

Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

New-Step {
    $Stepper.Test = Get-Process
}

New-Step {
    $Stepper.Test
}

New-Step {
    $Stepper.Test | Select-Object -Last 3
}

Stop-Stepper
