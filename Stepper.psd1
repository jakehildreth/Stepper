@{
    AliasesToExport=@()
    Author='Jake Hildreth'
    CmdletsToExport=@()
    CompanyName='Gilmour Technologies Ltd'
    CompatiblePSEditions=@('Desktop',        'Core')
    Copyright='(c) 2025 - 2026 Jake Hildreth, Gilmour Technologies Ltd. All rights reserved.'
    Description='A cross-platform PowerShell utility module for creating resumable, step-by-step scripts with automatic state persistence.'
    FunctionsToExport=@('ConvertTo-StepperScript',        'New-Step',        'New-StepperScript',        'Repair-StepperScript',        'Stop-Stepper',        'Test-StepperScript')
    GUID='2260142f-ef07-4749-a430-a2062efefbf6'
    ModuleVersion='2026.5.70453'
    PowerShellVersion='5.1'
    PrivateData=@{
        PSData=@{
            ExternalModuleDependencies=@('Microsoft.PowerShell.Utility',                'Microsoft.PowerShell.Management',                'Microsoft.PowerShell.Host')
            RequireLicenseAcceptance=$false
            Tags=@('Windows',                'MacOS',                'Linux')
        }
    }
    RequiredModules=@('Microsoft.PowerShell.Utility',        'Microsoft.PowerShell.Management',        'Microsoft.PowerShell.Host')
    RootModule='Stepper.psm1'
}
