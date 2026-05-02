@{
    AliasesToExport=@()
    Author='Jake Hildreth'
    CmdletsToExport=@()
    CompanyName='Gilmour Technologies Ltd'
    CompatiblePSEditions=@('Desktop',        'Core')
    Copyright='(c) 2025 - 2026 Jake Hildreth, Gilmour Technologies Ltd. All rights reserved.'
    Description='A cross-platform PowerShell utility module for creating resumable, step-by-step scripts with automatic state persistence.'
    FunctionsToExport=@('New-Step', 'Stop-Stepper', 'Test-StepperScript', 'Repair-StepperScript', 'New-StepperScript')
    GUID='2260142f-ef07-4749-a430-a2062efefbf6'
    ModuleVersion='2026.3.17.1944'
    PowerShellVersion='5.1'
    PrivateData=@{
        PSData=@{
            ExternalModuleDependencies=@('Microsoft.PowerShell.Utility',                'Microsoft.PowerShell.Management')
            RequireLicenseAcceptance=$false
            Tags=@('Windows',                'MacOS',                'Linux')
        }
    }
    RequiredModules=@('Microsoft.PowerShell.Utility',        'Microsoft.PowerShell.Management')
    RootModule='Stepper.psm1'
}
