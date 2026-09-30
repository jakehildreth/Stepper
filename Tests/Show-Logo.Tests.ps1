BeforeAll {
    # Show-Logo.ps1 renders the splash at dot-source time. Capture its Write-Host
    # output in a sandboxed scope that also hosts the mocks: the file runs at top
    # level, so Mock overrides inside the same ScriptBlock catch its Write-Host calls.
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ShowLogoPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private/Show-Logo.ps1'

    function Invoke-ShowLogoCapture {
        param([string]$ManifestContent)
        $scriptBlock = {
            param($Content, $LogoPath)
            Mock Write-Host { param($Object) $script:Captured += $Object }
            if ($null -ne $Content) {
                Mock Import-PowerShellDataFile { param($Path) @{ ModuleVersion = $Content } }
                Mock Test-Path { param($Path) $Path -like '*Stepper.psd1' } -ParameterFilter { $Path -like '*Stepper.psd1' }
            } else {
                Mock Test-Path { param($Path) $false } -ParameterFilter { $Path -like '*Stepper.psd1' }
            }
            $script:Captured = @()
            . $LogoPath
            $script:Captured
        }
        & $scriptBlock $ManifestContent $script:ShowLogoPath
    }
}

Describe 'Show-Logo version display' {
    It 'Writes the manifest version under the logo when Stepper.psd1 exists' {
        $output = Invoke-ShowLogoCapture -ManifestContent '2099.1.10000'
        $output | Where-Object { $_ -match 'v2099\.1\.10000' } | Should -Not -BeNullOrEmpty
    }

    It 'Writes no version line when no Stepper.psd1 is found' {
        $output = Invoke-ShowLogoCapture -ManifestContent $null
        $output | Where-Object { $_ -match 'v\d+\.\d+' } | Should -BeNullOrEmpty
    }
}
