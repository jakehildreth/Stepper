BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepperFindingCatalog.ps1"
    . "$ModulePath/Private/New-StepperIssue.ps1"
    . "$ModulePath/Private/Get-StepperScriptFindings.ps1"
    . "$ModulePath/Private/New-StepperBackup.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Invoke-StepperScriptRepair.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"
    . "$ModulePath/Public/Repair-StepperScript.ps1"

    function New-TempScript {
        param([string[]]$Lines)

        $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $Lines -join [System.Environment]::NewLine |
            Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
        return $path
    }

    function Remove-TempScript {
        param([string]$Path)

        $directory = Split-Path -Parent $Path
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$Path.stepper" -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $directory -Filter "$baseName.*.ps1.bak" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $Help = @(
        '<#'
        '.SYNOPSIS'
        '    Test script.'
        '#>'
    )
    $Guard = 'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
}

Describe 'Repair-StepperScript' -Tag 'Unit' {
    It 'returns the compatible validation properties and repair metadata' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            '#region Stepper ignore'
            $Guard
            'Start-Stepper'
            '#endregion Stepper ignore'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -Path $path

            $result.PSObject.Properties.Name | Should -Contain 'Path'
            $result.PSObject.Properties.Name | Should -Contain 'IsValid'
            $result.PSObject.Properties.Name | Should -Contain 'Issues'
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'BackupPath'
            $result.PSObject.Properties.Name | Should -Contain 'AppliedRepairs'
            $result.PSObject.Properties.Name | Should -Contain 'PlannedRepairs'
            $result.Changed | Should -BeFalse
            $result.AppliedRepairs | Should -BeNullOrEmpty
            $result.PlannedRepairs | Should -BeNullOrEmpty
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'repairs missing param, guard, and Start in one transaction' {
        $path = New-TempScript @(
            $Help
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        try {
            Mock Set-Content {
                [System.IO.File]::WriteAllText(
                    $LiteralPath,
                    [string]$Value,
                    [System.Text.UTF8Encoding]::new($false)
                )
            }

            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false
            $content = Get-Content -LiteralPath $path -Raw
            $backupFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter "$([System.IO.Path]::GetFileNameWithoutExtension($path)).*.ps1.bak")

            $result.Changed | Should -BeTrue
            $result.AppliedRepairs | Should -Be @(
                'MissingParamBlock'
                'MissingInstallGuard'
                'MissingStartStepper'
            )
            $result.PlannedRepairs | Should -Be $result.AppliedRepairs
            $result.IsValid | Should -BeTrue
            $content | Should -Match '(?s)\[CmdletBinding\(\)\]\s*param\(\)\s*#region Stepper ignore'
            $content | Should -Match 'Install-Module Stepper[^\r\n]*\r?\nStart-Stepper\r?\n#endregion Stepper ignore'
            $backupFiles | Should -HaveCount 1
            $result.BackupPath | Should -Be $backupFiles[0].FullName
            Should -Invoke Set-Content -Times 1 -Exactly -Scope It
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'adds CmdletBinding to an existing param block without replacing its parameters' {
        $path = New-TempScript @(
            $Help
            'param([string]$Name)'
            '#region Stepper ignore'
            $Guard
            'Start-Stepper'
            '#endregion Stepper ignore'
            'New-Step { Write-Host $Name }'
            'Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false
            $content = Get-Content -LiteralPath $path -Raw

            $result.AppliedRepairs | Should -Be @('MissingCmdletBinding')
            $content | Should -Match '(?s)\[CmdletBinding\(\)\]\s*param\(\[string\]\$Name\)'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'inserts a missing param block after using statements' {
        $path = New-TempScript @(
            'using namespace System'
            $Help
            'New-Step { Write-Host ([DateTime]::UtcNow) }'
            'Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false
            $content = Get-Content -LiteralPath $path -Raw
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $path,
                [ref]$null,
                [ref]$parseErrors
            )

            $result.AppliedRepairs | Should -Contain 'MissingParamBlock'
            $content | Should -Match '(?s)^using namespace System.*\[CmdletBinding\(\)\]\s*param\(\)'
            $parseErrors | Should -HaveCount 0
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'wraps a canonical guard and inserts Start immediately after it' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            $Guard
            '$StepperConversionComplete = $true'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false
            $content = Get-Content -LiteralPath $path -Raw

            $result.AppliedRepairs | Should -Be @(
                'MissingBootstrapRegion'
                'MissingStartStepper'
            )
            $content | Should -Match 'Install-Module Stepper[^\r\n]*\r?\nStart-Stepper\r?\n#endregion Stepper ignore'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'wraps a module-qualified canonical guard' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            'if (-not (Microsoft.PowerShell.Core\Get-Module Stepper)) { PowerShellGet\Install-Module Stepper -Force }'
            '$StepperConversionComplete = $true'
            'Stepper\New-Step { Write-Host "step" }'
            'Stepper\Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false

            $result.AppliedRepairs | Should -Contain 'MissingBootstrapRegion'
            $result.Changed | Should -BeTrue
            (Test-StepperScript -ScriptPath $path).Issues.Code | Should -Not -Contain 'MissingBootstrapRegion'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'does not repair a bootstrap region or Start when the guard is misplaced' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            'if ($true) {'
            "    $Guard"
            '}'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        try {
            $before = Get-Content -LiteralPath $path -Raw
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false

            $result.Changed | Should -BeFalse
            $result.PlannedRepairs | Should -BeNullOrEmpty
            Get-Content -LiteralPath $path -Raw | Should -Be $before
            $result.Issues.Code | Should -Contain 'MisplacedInstallGuard'
            $result.Issues.Code | Should -Contain 'MissingBootstrapRegion'
            $result.Issues.Code | Should -Contain 'MissingStartStepper'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'applies safe additions while unrelated findings remain' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            'Stop-Stepper'
        )
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false

            $result.Changed | Should -BeTrue
            $result.AppliedRepairs | Should -Be @(
                'MissingInstallGuard'
                'MissingStartStepper'
            )
            $result.IsValid | Should -BeFalse
            $result.Issues.Code | Should -Contain 'NoSteps'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'never auto-fixes MissingCbh or MissingStopStepper warnings' {
        $path = New-TempScript @(
            '[CmdletBinding()]'
            'param()'
            '#region Stepper ignore'
            $Guard
            'Start-Stepper'
            '#endregion Stepper ignore'
            'New-Step { Write-Host "step" }'
        )
        try {
            $before = Get-Content -LiteralPath $path -Raw
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false

            $result.Changed | Should -BeFalse
            Get-Content -LiteralPath $path -Raw | Should -Be $before
            $result.Issues.Code | Should -Contain 'MissingCbh'
            $result.Issues.Code | Should -Contain 'MissingStopStepper'
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'reports planned repairs under WhatIf without backup, write, state removal, or retest effects' {
        $path = New-TempScript @(
            $Help
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        $statePath = Get-StepperStatePath -ScriptPath $path
        Set-Content -LiteralPath $statePath -Value '{"stale":true}' -NoNewline
        try {
            $before = Get-Content -LiteralPath $path -Raw
            $script:currentRepairTestResult = Test-StepperScript -ScriptPath $path
            Mock Test-StepperScript { $script:currentRepairTestResult }

            $result = Repair-StepperScript -ScriptPath $path -WhatIf
            $backupFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter "$([System.IO.Path]::GetFileNameWithoutExtension($path)).*.ps1.bak")

            $result.Changed | Should -BeFalse
            $result.BackupPath | Should -BeNullOrEmpty
            $result.AppliedRepairs | Should -BeNullOrEmpty
            $result.PlannedRepairs | Should -Be @(
                'MissingParamBlock'
                'MissingInstallGuard'
                'MissingStartStepper'
            )
            $result.Issues.Code | Should -Contain 'MissingParamBlock'
            Get-Content -LiteralPath $path -Raw | Should -Be $before
            Test-Path -LiteralPath $statePath | Should -BeTrue
            $backupFiles | Should -HaveCount 0
            Should -Invoke Test-StepperScript -Times 1 -Exactly -Scope It
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'removes stale state after a successful write' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        $statePath = Get-StepperStatePath -ScriptPath $path
        Set-Content -LiteralPath $statePath -Value '{"stale":true}' -NoNewline
        try {
            $result = Repair-StepperScript -ScriptPath $path -Confirm:$false

            $result.Changed | Should -BeTrue
            Test-Path -LiteralPath $statePath | Should -BeFalse
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'prevents the write when backup creation fails' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        try {
            $before = Get-Content -LiteralPath $path -Raw
            Mock New-StepperBackup { throw 'simulated backup failure' }

            { Repair-StepperScript -ScriptPath $path -Confirm:$false } |
                Should -Throw '*script was not changed*'
            Get-Content -LiteralPath $path -Raw | Should -Be $before
        }
        finally {
            Remove-TempScript $path
        }
    }

    It 'requires the supplied Test result to match the repaired path' {
        $firstPath = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
        $secondPath = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
        try {
            $testResult = Test-StepperScript -ScriptPath $firstPath

            { Invoke-StepperScriptRepair -ScriptPath $secondPath -TestResult $testResult -Confirm:$false } |
                Should -Throw '*does not match script path*'
        }
        finally {
            Remove-TempScript $firstPath
            Remove-TempScript $secondPath
        }
    }

    It 'accepts relative and tilde paths through the public command' {
        $path = New-TempScript @(
            $Help
            '[CmdletBinding()]'
            'param()'
            '#region Stepper ignore'
            $Guard
            'Start-Stepper'
            '#endregion Stepper ignore'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        )
        $directory = Split-Path -Parent $path
        $fileName = Split-Path -Leaf $path
        Push-Location $directory
        try {
            (Repair-StepperScript -ScriptPath "./$fileName").Path | Should -Be $path
        }
        finally {
            Pop-Location
            Remove-TempScript $path
        }

        $homeFileName = "StepperRepair_$([guid]::NewGuid().ToString('N')).ps1"
        $homePath = Join-Path $HOME $homeFileName
        @(
            $Help
            '[CmdletBinding()]'
            'param()'
            '#region Stepper ignore'
            $Guard
            'Start-Stepper'
            '#endregion Stepper ignore'
            'New-Step { Write-Host "step" }'
            'Stop-Stepper'
        ) -join [System.Environment]::NewLine |
            Set-Content -LiteralPath $homePath -Encoding UTF8 -NoNewline
        try {
            (Repair-StepperScript -ScriptPath "~/$homeFileName").Path | Should -Be $homePath
        }
        finally {
            Remove-TempScript $homePath
        }
    }
}
