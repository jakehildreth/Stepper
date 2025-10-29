@{
    AliasesToExport=@()
    Author='Jake Hildreth'
    CmdletsToExport=@()
    CompanyName='CompanyName'
    CompatiblePSEditions=@('Desktop',        'Core')
    Copyright='(c) 2025 - 2025. All rights reserved.'
    Description='A module to help create step-by-step modules that guide users through complex tasks.'
    FileList=@('Stepper.psm1',        'Stepper.psd1')
    FunctionsToExport=@('Get-StepperSteps',        'New-StepperConfig',        'New-StepperScript',        'New-StepperStep',        'Reset-StepperState',        'Show-StepperStatus',        'Start-Stepper')
    GUID='703e39b3-f720-48f1-94fc-3cd1ee10ab74'
    ModuleVersion='2025.10.29'
    PowerShellVersion='5.1'
    PrivateData=@{
        PSData=@{
            ExternalModuleDependencies=@('Microsoft.PowerShell.Utility',                'Microsoft.PowerShell.Archive',                'Microsoft.PowerShell.Management',                'Microsoft.PowerShell.Security')
            LicenseUri='https://opensource.org/licenses/MIT'
            Tags=@('Windows',                'MacOS',                'Linux')
        }
    }
    RequiredModules=@('Microsoft.PowerShell.Utility',        'Microsoft.PowerShell.Archive',        'Microsoft.PowerShell.Management',        'Microsoft.PowerShell.Security')
    RootModule='Stepper.psm1'
}
