BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Get-StepperFindingCatalog.ps1"
    . "$ModulePath/Private/New-StepperIssue.ps1"
    . "$ModulePath/Private/Get-StepperScriptFindings.ps1"
    . "$ModulePath/Private/Get-StepperInitInsertionIndex.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"

    function New-TempScript {
        param([string[]]$Lines)
        $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $Lines -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
        return $path
    }

    # A fully valid Stepper script (passes all checks). Start-Stepper is required
    # whenever New-Step is present, so the valid script includes it inside the
    # ignore region, after the install guard.
    $ValidScript = @(
        '<#'
        '.SYNOPSIS'
        '    My script.'
        '.NOTES'
        '    Managed by Stepper. Use New-Step blocks to define resumable steps.'
        '#>'
        '[CmdletBinding()]'
        'param()'
        '#region Stepper ignore'
        'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
        'Start-Stepper'
        '#endregion Stepper ignore'
        'New-Step { Write-Host "step 1" }'
        'Stop-Stepper'
    ) -join [System.Environment]::NewLine
}

Describe 'Test-StepperScript' -Tag 'Unit' {

    Context 'Return type' {
        It 'Should return a PSCustomObject' {
            # Arrange
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result | Should -BeOfType [PSCustomObject]
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should have Path, IsValid, and Issues properties' {
            # Arrange
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.PSObject.Properties.Name | Should -Contain 'Path'
                $result.PSObject.Properties.Name | Should -Contain 'IsValid'
                $result.PSObject.Properties.Name | Should -Contain 'Issues'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should set Path to the resolved script path' {
            # Arrange
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.Path | Should -Be $path
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should accept -Path as an alias for -ScriptPath' {
            # Arrange
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                # Act / Assert; should not throw ParameterNotFound
                { Test-StepperScript -Path $path } | Should -Not -Throw
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should never modify the script file' {
            # Arrange
            $path = New-TempScript @(
                'Write-Host "no cmdletbinding"'
                'Stop-Stepper'
            )
            try {
                $before = Get-Content -Path $path -Raw
                # Act
                Test-StepperScript -ScriptPath $path | Out-Null
                # Assert
                $after = Get-Content -Path $path -Raw
                $after | Should -Be $before
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Valid script' {
        It 'Should return IsValid = $true with no issues for a fully-conformant script' {
            # Arrange
            $path = New-TempScript ($ValidScript -split [System.Environment]::NewLine)
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeTrue
                $result.Issues  | Should -HaveCount 0
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'MissingCmdletBinding (Error)' {
        It 'Should report MissingCmdletBinding when [CmdletBinding()] is absent' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeFalse
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'MissingCmdletBinding'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'MissingCmdletBinding issue should have Severity = Error' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $issue = $result.Issues | Where-Object Code -EQ 'MissingCmdletBinding'
                $issue.Severity | Should -Be 'Error'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'MissingInstallGuard (Error)' {
        It 'Should report MissingInstallGuard when no Install-Module Stepper line is present' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeFalse
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'MissingInstallGuard'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'MissingInstallGuard issue should have Severity = Error' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $issue = $result.Issues | Where-Object Code -EQ 'MissingInstallGuard'
                $issue.Severity | Should -Be 'Error'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'MissingCbh (Warning)' {
        It 'Should report MissingCbh when script has no comment-based help' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'MissingCbh'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'MissingCbh issue should have Severity = Warning' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $issue = $result.Issues | Where-Object Code -EQ 'MissingCbh'
                $issue.Severity | Should -Be 'Warning'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should not report MissingCbh when .SYNOPSIS is present' {
            # Arrange
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    Has help.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Not -Contain 'MissingCbh'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'MissingStopStepper (Warning)' {
        It 'Should report MissingStopStepper when Stop-Stepper is absent' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'MissingStopStepper'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'MissingStopStepper issue should have Severity = Warning' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $issue = $result.Issues | Where-Object Code -EQ 'MissingStopStepper'
                $issue.Severity | Should -Be 'Warning'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'NoSteps (Error)' {
        It 'Should report NoSteps when script has no New-Step calls' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'NoSteps'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'NoSteps issue should have Severity = Error' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $issue = $result.Issues | Where-Object Code -EQ 'NoSteps'
                $issue.Severity | Should -Be 'Error'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'IsValid semantics' {
        It 'Should be $false when any Error-severity issue exists' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeFalse
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should be $true when only Warning-severity issues exist' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { Write-Host "hi" }'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert - MissingCbh and MissingStopStepper are warnings only
                $result.IsValid | Should -BeTrue
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Each issue has a Message property' {
        It 'Should have a non-empty Message on each issue' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                foreach ($issue in $result.Issues) {
                    $issue.Message | Should -Not -BeNullOrEmpty
                }
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Path resolution' {
        It 'Should accept a relative path (./script.ps1)' {
            # Arrange
            $path = New-TempScript ($ValidScript -split [System.Environment]::NewLine)
            $dir  = Split-Path -Parent $path
            $file = Split-Path -Leaf $path
            Push-Location $dir
            try {
                # Act
                $result = Test-StepperScript -ScriptPath "./$file"
                # Assert
                $result.IsValid | Should -BeTrue
            }
            finally {
                Pop-Location
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }

        It 'Should accept a tilde path (~/script.ps1)' {
            # Arrange
            $fileName = "StepperPathTest_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
            $absPath  = Join-Path $HOME $fileName
            $ValidScript | Set-Content -Path $absPath -Encoding UTF8 -NoNewline
            try {
                # Act
                $result = Test-StepperScript -ScriptPath "~/$fileName"
                # Assert
                $result.IsValid | Should -BeTrue
            }
            finally {
                Remove-Item $absPath -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'MissingStartStepper rule' -Tag 'Unit' {
    Context 'Detection' {
        It 'Flags a script with New-Step but no Start-Stepper as an Error' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'New-Step { Write-Host "x" }'
                'Stop-Stepper'
            )
            $result = Test-StepperScript -ScriptPath $path
            $issue = $result.Issues | Where-Object Code -EQ 'MissingStartStepper'
            $issue | Should -Not -BeNullOrEmpty
            $issue.Severity | Should -Be 'Error'
            $result.IsValid | Should -BeFalse
        }

        It 'Does not flag a script that has Start-Stepper' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { Write-Host "x" }'
                'Stop-Stepper'
            )
            $result = Test-StepperScript -ScriptPath $path
            $result.Issues | Where-Object Code -EQ 'MissingStartStepper' | Should -BeNullOrEmpty
        }

        It 'Does not cascade Stepper findings for a script with no lifecycle command' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'Write-Host "no steps here"'
            )
            try {
                $result = Test-StepperScript -ScriptPath $path
                $result.Issues.Code | Should -Be @('NotStepperScript')
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Canonical Stepper finding catalog' -Tag 'Unit' {
    It 'Contains every approved finding exactly once' {
        $expected = @(
            'NotStepperScript', 'ParseError', 'MissingParamBlock', 'MissingCmdletBinding',
            'MissingInstallGuard', 'InvalidInstallGuard', 'MisplacedInstallGuard',
            'MissingBootstrapRegion', 'MalformedIgnoreRegion', 'MissingStartStepper',
            'DuplicateStartStepper', 'NestedStartStepper', 'StartOutsideBootstrapRegion',
            'StartBeforeInstallGuard', 'StartAfterExecutableCode', 'NoSteps',
            'NestedNewStep', 'MissingStepScriptBlock', 'NewStepBeforeStart',
            'NewStepAfterStop', 'DuplicateStopStepper', 'NestedStopStepper',
            'MisplacedStopStepper', 'ExecutableCodeAfterStop', 'UnmanagedCode',
            'MissingCbh', 'MissingStopStepper'
        )
        $catalog = Get-StepperFindingCatalog
        @($catalog.Keys) | Should -HaveCount $expected.Count
        foreach ($code in $expected) { $catalog.Contains($code) | Should -BeTrue }
    }

    It 'Returns location and remediation properties on every finding' {
        $path = New-TempScript @('Stop-Stepper')
        try {
            $result = Test-StepperScript -ScriptPath $path
            foreach ($issue in $result.Issues) {
                $issue.PSObject.Properties.Name | Should -Contain 'Location'
                $issue.PSObject.Properties.Name | Should -Contain 'Remediation'
                $issue.Remediation | Should -BeIn @('None', 'Deterministic', 'Interactive')
            }
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }
}

Describe 'Canonical structural findings' -Tag 'Unit' {
    It 'Returns only located ParseError findings when parsing fails' {
        $path = New-TempScript @('Start-Stepper', 'if (')
        try {
            $result = Test-StepperScript -ScriptPath $path
            $result.Issues.Code | Select-Object -Unique | Should -Be @('ParseError')
            $result.Issues[0].Location.StartLine | Should -BeGreaterThan 0
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects malformed nested Stepper-ignore regions' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()',
            '#region Stepper ignore', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore', '#endregion Stepper ignore',
            'New-Step { }', 'Stop-Stepper'
        )
        try {
            (Test-StepperScript $path).Issues.Code | Should -Contain 'MalformedIgnoreRegion'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects duplicate and nested Start calls' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore',
            'if ($true) { Initialize-Stepper }', 'New-Step { }', 'Stop-Stepper'
        )
        try {
            $codes = (Test-StepperScript $path).Issues.Code
            $codes | Should -Contain 'DuplicateStartStepper'
            $codes | Should -Contain 'NestedStartStepper'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects a Start call outside the bootstrap region' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            '#endregion Stepper ignore', 'Start-Stepper', 'New-Step { }', 'Stop-Stepper'
        )
        try {
            (Test-StepperScript $path).Issues.Code | Should -Contain 'StartOutsideBootstrapRegion'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects nested and scriptblock-less New-Step calls' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore',
            'if ($true) { New-Step }', 'Stop-Stepper'
        )
        try {
            $codes = (Test-StepperScript $path).Issues.Code
            $codes | Should -Contain 'NestedNewStep'
            $codes | Should -Contain 'MissingStepScriptBlock'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects New-Step and executable code after Stop without duplicate unmanaged findings' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore',
            'New-Step { }', 'Stop-Stepper', 'Write-Host "after"', 'New-Step { }'
        )
        try {
            $result = Test-StepperScript $path
            $result.Issues.Code | Should -Contain 'NewStepAfterStop'
            $result.Issues.Code | Should -Contain 'ExecutableCodeAfterStop'
            $result.Issues.Code | Should -Contain 'MisplacedStopStepper'
            @($result.Issues | Where-Object Code -EQ 'UnmanagedCode') | Should -HaveCount 0
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Detects duplicate and nested Stop calls' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore',
            'New-Step { Stop-Stepper }', 'Stop-Stepper', 'Stop-Stepper'
        )
        try {
            $codes = (Test-StepperScript $path).Issues.Code
            $codes | Should -Contain 'NestedStopStepper'
            $codes | Should -Contain 'DuplicateStopStepper'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Returns one located UnmanagedCode finding for adjacent root statements' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore',
            'Write-Host "one"', '', '# comment', 'Write-Host "two"',
            'New-Step { }', 'Stop-Stepper'
        )
        try {
            $issues = @((Test-StepperScript $path).Issues | Where-Object Code -EQ 'UnmanagedCode')
            $issues | Should -HaveCount 1
            $issues[0].Location.StartLine | Should -Be 7
            $issues[0].Location.EndLine | Should -Be 10
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Rejects an install command in an else branch or a non-negated availability branch' {
        foreach ($guard in @(
            'if (-not (Get-Module Stepper)) { Write-Host absent } else { Install-Module Stepper }',
            'if ((Get-Module Stepper) -and -not $false) { Install-Module Stepper }'
        )) {
            $path = New-TempScript @(
                '[CmdletBinding()]', 'param()', '#region Stepper ignore', $guard,
                'Start-Stepper', '#endregion Stepper ignore', 'New-Step { }', 'Stop-Stepper'
            )
            try { (Test-StepperScript $path).Issues.Code | Should -Contain 'InvalidInstallGuard' }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    It 'Rejects a guard whose boolean condition can install while Stepper is available' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if ((-not (Get-Module Stepper)) -or $true) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore', 'New-Step { }', 'Stop-Stepper'
        )
        try { (Test-StepperScript $path).Issues.Code | Should -Contain 'InvalidInstallGuard' }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Treats lifecycle commands in mixed pipelines as nested and preserves unmanaged code findings' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Write-Output x | Start-Stepper', '#endregion Stepper ignore',
            'New-Step { } | Write-Output', 'Stop-Stepper | Write-Output'
        )
        try {
            $codes = (Test-StepperScript $path).Issues.Code
            $codes | Should -Contain 'NestedStartStepper'
            $codes | Should -Contain 'NestedNewStep'
            $codes | Should -Contain 'NestedStopStepper'
            $codes | Should -Contain 'UnmanagedCode'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Recognizes module-qualified lifecycle commands' {
        $path = New-TempScript @(
            '<#', '.SYNOPSIS', 's', '#>', '[CmdletBinding()]', 'param()',
            '#region Stepper ignore',
            'if (-not (Microsoft.PowerShell.Core\Get-Module Stepper)) { PowerShellGet\Install-Module Stepper -Force }',
            'Stepper\Start-Stepper', '#endregion Stepper ignore',
            'Stepper\New-Step { }', 'Stepper\Stop-Stepper'
        )
        try { (Test-StepperScript $path).IsValid | Should -BeTrue }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Reports a valid guard as misplaced when executable code precedes it' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', 'Write-Host before', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore', 'New-Step { }', 'Stop-Stepper'
        )
        try { (Test-StepperScript $path).Issues.Code | Should -Contain 'MisplacedInstallGuard' }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }

    It 'Does not report MissingStopStepper when a nested Stop call is present' {
        $path = New-TempScript @(
            '[CmdletBinding()]', 'param()', '#region Stepper ignore',
            'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }',
            'Start-Stepper', '#endregion Stepper ignore', 'New-Step { Stop-Stepper }'
        )
        try {
            $codes = (Test-StepperScript $path).Issues.Code
            $codes | Should -Contain 'NestedStopStepper'
            $codes | Should -Not -Contain 'MissingStopStepper'
        }
        finally { Remove-Item $path -ErrorAction SilentlyContinue }
    }
}
