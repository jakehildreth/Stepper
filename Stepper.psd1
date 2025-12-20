@{
    AliasesToExport=@()
    Author='Jake Hildreth'
    CmdletsToExport=@()
    CompanyName='Gilmour Technologies Ltd'
    CompatiblePSEditions=@('Desktop',        'Core')
    Copyright='(c) 2025 - 2025 Author @ Gilmour Technologies Ltd. All rights reserved.'
    Description='A PowerShell module for creating resumable, step-by-step automation scripts with automatic state persistence and cross-platform support.'
    FunctionsToExport=@('New-Step',        'Stop-Stepper')
    GUID='2260142f-ef07-4749-a430-a2062efefbf6'
    ModuleVersion='2025.12.20.1057'
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
