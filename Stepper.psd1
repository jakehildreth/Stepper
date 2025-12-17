@{
    AliasesToExport      = @()
    Author               = 'Jake Hildreth'
    CmdletsToExport      = @()
    CompanyName          = 'Unknown'
    CompatiblePSEditions = @('Desktop', 'Core')
    Copyright            = '(c) 2025 Jake Hildreth. All rights reserved.'
    Description          = 'A PowerShell module for creating resumable scripts that can recover from failures by tracking completed steps.'
    FunctionsToExport    = @('New-Step', 'Stop-Stepper')
    GUID                 = '2260142f-ef07-4749-a430-a2062efefbf6'
    ModuleVersion        = '0.1.0'
    PowerShellVersion    = '5.1'
    PrivateData          = @{
        PSData = @{
            Tags = @('Resumable', 'State', 'Recovery', 'Steps', 'Automation')
            LicenseUri = 'https://github.com/jakehildreth/Stepper/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jakehildreth/Stepper'
        }
    }
    RootModule           = 'Stepper.psm1'
}
