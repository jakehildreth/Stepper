@{
    AliasesToExport=@()
    Author='Author'
    CmdletsToExport=@()
    CompanyName='CompanyName'
    CompatiblePSEditions=@('Desktop',        'Core')
    Copyright='(c) 2011 - 2025 Author @ CompanyName. All rights reserved.'
    Description='Simple project Stepper'
    FunctionsToExport=@('New-Step',        'Stop-Stepper')
    GUID='2260142f-ef07-4749-a430-a2062efefbf6'
    ModuleVersion='1.0.0'
    PowerShellVersion='5.1'
    PrivateData=@{
        PSData=@{
            ExternalModuleDependencies=@('Microsoft.PowerShell.Utility',                'Microsoft.PowerShell.Management')
            Tags=@('Windows',                'MacOS',                'Linux')
        }
    }
    RequiredModules=@('Microsoft.PowerShell.Utility',        'Microsoft.PowerShell.Management')
    RootModule='Stepper.psm1'
}
