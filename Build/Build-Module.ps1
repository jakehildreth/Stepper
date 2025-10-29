param (
    # A CalVer string if you need to manually override the default yyyy.M.d version string.
    [string]$CalVer,
    [switch]$PublishToPSGallery,
    [string]$PSGalleryAPIPath
)

if (Get-Module -Name 'PSPublishModule' -ListAvailable) {
    Write-Information 'PSPublishModule is installed.'
} else {
    Write-Information 'PSPublishModule is not installed. Attempting installation.'
    try {
        Install-Module -Name Pester -AllowClobber -Scope CurrentUser -SkipPublisherCheck -Force
        Install-Module -Name PSPublishModule -AllowClobber -Scope CurrentUser -Force
    } catch {
        Write-Error 'PSPublishModule installation failed.'
    }
}

Update-Module -Name PSPublishModule
Import-Module -Name PSPublishModule -Force

$CopyrightYear = if ($Calver) { $CalVer.Split('.')[0] } else { (Get-Date -Format yyyy) }

Build-Module -ModuleName 'Stepper' {
    # Usual defaults as per standard module
    $Manifest = [ordered] @{
        ModuleVersion        = if ($Calver) { $CalVer } else { (Get-Date -Format yyyy.M.d.Hmm -AsUTC) }
        CompatiblePSEditions = @('Desktop', 'Core')
        GUID                 = '703e39b3-f720-48f1-94fc-3cd1ee10ab74'
        Author               = 'Jake Hildreth'
        CompanyName          = 'CompanyName'
        Copyright            = "(c) 2025 - $CopyrightYear. All rights reserved."
        Description          = 'A module to help create step-by-step modules that guide users through complex tasks.'
        LicenseURI           = 'https://opensource.org/licenses/MIT'
        PowerShellVersion    = '5.1'
        Tags                 = @('Windows', 'MacOS', 'Linux')
    }
    New-ConfigurationManifest @Manifest

    # Add standard module dependencies (directly, but can be used with loop as well)
    #New-ConfigurationModule -Type RequiredModule -Name 'PSSharedGoods' -Guid 'Auto' -Version 'Latest'

    # Add external module dependencies, using loop for simplicity
    foreach ($Module in @('Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Archive', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Security')) {
        New-ConfigurationModule -Type ExternalModule -Name $Module
    }

    # Add approved modules, that can be used as a dependency, but only when specific function from those modules is used
    # And on that time only that function and dependant functions will be copied over
    # Keep in mind it has it's limits when "copying" functions such as it should not depend on DLLs or other external files
    #New-ConfigurationModule -Type ApprovedModule -Name 'PSSharedGoods', 'PSWriteColor', 'Connectimo', 'PSUnifi', 'PSWebToolbox', 'PSMyPassword'

    #New-ConfigurationModuleSkip -IgnoreFunctionName 'Invoke-Formatter', 'Find-Module' -IgnoreModuleName 'platyPS'

    $ConfigurationFormat = [ordered] @{
        RemoveComments                              = $false

        PlaceOpenBraceEnable                        = $true
        PlaceOpenBraceOnSameLine                    = $true
        PlaceOpenBraceNewLineAfter                  = $true
        PlaceOpenBraceIgnoreOneLineBlock            = $false

        PlaceCloseBraceEnable                       = $true
        PlaceCloseBraceNewLineAfter                 = $true
        PlaceCloseBraceIgnoreOneLineBlock           = $false
        PlaceCloseBraceNoEmptyLineBefore            = $true

        UseConsistentIndentationEnable              = $true
        UseConsistentIndentationKind                = 'space'
        UseConsistentIndentationPipelineIndentation = 'IncreaseIndentationAfterEveryPipeline'
        UseConsistentIndentationIndentationSize     = 4

        UseConsistentWhitespaceEnable               = $true
        UseConsistentWhitespaceCheckInnerBrace      = $true
        UseConsistentWhitespaceCheckOpenBrace       = $true
        UseConsistentWhitespaceCheckOpenParen       = $true
        UseConsistentWhitespaceCheckOperator        = $true
        UseConsistentWhitespaceCheckPipe            = $true
        UseConsistentWhitespaceCheckSeparator       = $true

        AlignAssignmentStatementEnable              = $true
        AlignAssignmentStatementCheckHashtable      = $true

        UseCorrectCasingEnable                      = $true
    }
    # format PSD1 and PSM1 files when merging into a single file
    # enable formatting is not required as Configuration is provided
    # DISABLED: Causes issues with PSScriptAnalyzer inside VSCode
    # New-ConfigurationFormat -ApplyTo 'OnMergePSM1', 'OnMergePSD1' -Sort None @ConfigurationFormat
    # format PSD1 and PSM1 files within the module
    # enable formatting is required to make sure that formatting is applied (with default settings)
    # DISABLED: Causes issues with PSScriptAnalyzer inside VSCode
    # New-ConfigurationFormat -ApplyTo 'DefaultPSD1', 'DefaultPSM1' -EnableFormatting -Sort None
    # when creating PSD1 use special style without comments and with only required parameters
    New-ConfigurationFormat -ApplyTo 'DefaultPSD1', 'OnMergePSD1' -PSD1Style 'Minimal'

    # configuration for documentation, at the same time it enables documentation processing
    New-ConfigurationDocumentation -Enable:$false -StartClean -UpdateWhenNew -PathReadme 'Docs\Readme.md' -Path 'Docs'

    New-ConfigurationImportModule -ImportSelf -ImportRequiredModules

    New-ConfigurationBuild -Enable:$true -SignModule:$false -DeleteTargetModuleBeforeBuild -MergeModuleOnBuild -MergeFunctionsFromApprovedModules -DoNotAttemptToFixRelativePaths

    # New-ConfigurationArtefact -Type Unpacked -Enable -Path "$PSScriptRoot\..\Artefacts\Unpacked"
    # New-ConfigurationArtefact -Type Packed -Enable -Path "$PSScriptRoot\..\Artefacts\Packed" -IncludeTagName 

    # global options for publishing to github/psgallery
    if($PublishToPSGallery) {   
        New-ConfigurationPublish -Type PowerShellGallery -FilePath $PSGalleryAPIPath
    }
}
