BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/New-StepperIssue.ps1"
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

    Context 'UninitializedStepper detection' {
        It 'Flags a converted $Stepper.<Var> assignment before the first New-Step with no initializer' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                '$Stepper.Name = Read-Host "Name?"'
                'New-Step { Write-Host $Stepper.Name }'
                'Stop-Stepper'
            )
            try {
                $r = Test-StepperScript -ScriptPath $path
                $issue = $r.Issues | Where-Object Code -EQ 'UninitializedStepper'
                $issue | Should -Not -BeNullOrEmpty
                $issue.Severity | Should -Be 'Error'
                $r.IsValid | Should -BeFalse
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Does not flag when the initializer precedes the first unmanaged $Stepper assignment' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'if ($null -eq $Stepper) { $Stepper = @{} }'
                '$Stepper.Name = Read-Host "Name?"'
                'New-Step { Write-Host $Stepper.Name }'
                'Stop-Stepper'
            )
            try {
                $r = Test-StepperScript -ScriptPath $path
                $r.Issues | Where-Object Code -EQ 'UninitializedStepper' | Should -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Does not flag when $Stepper is only assigned inside New-Step blocks' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { $Stepper.Name = "x" }'
                'New-Step { Write-Host $Stepper.Name }'
                'Stop-Stepper'
            )
            try {
                $r = Test-StepperScript -ScriptPath $path
                $r.Issues | Where-Object Code -EQ 'UninitializedStepper' | Should -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Does not flag a script with no $Stepper member assignments' {
            $path = New-TempScript ($ValidScript -split [System.Environment]::NewLine)
            try {
                $r = Test-StepperScript -ScriptPath $path
                $r.Issues | Where-Object Code -EQ 'UninitializedStepper' | Should -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Flags an unmanaged $Stepper assignment even when a blank New-Step bootstrap precedes it' {
            # Regression: a blank New-Step added as a bootstrap becomes the "first"
            # step, so a line-order predicate goes blind to the real assignment that
            # follows it. Detection must key off unmanaged code, not line order.
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { }'
                '$Stepper.Name = Read-Host "Name?"'
                'New-Step { Write-Host $Stepper.Name }'
                'Stop-Stepper'
            )
            try {
                $r = Test-StepperScript -ScriptPath $path
                $r.Issues | Where-Object Code -EQ 'UninitializedStepper' | Should -Not -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Flags a $Stepper assignment inside a Stepper ignore region (unmanaged by definition)' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                '#region Stepper ignore'
                '$Stepper.Name = Read-Host "Name?"'
                '#endregion Stepper ignore'
                'New-Step { Write-Host $Stepper.Name }'
                'Stop-Stepper'
            )
            try {
                $r = Test-StepperScript -ScriptPath $path
                $r.Issues | Where-Object Code -EQ 'UninitializedStepper' | Should -Not -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

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

    Context 'NoSteps (Warning)' {
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

        It 'NoSteps issue should have Severity = Warning' {
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
                $issue.Severity | Should -Be 'Warning'
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
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Test-StepperScript -ScriptPath $path
                # Assert - only NoSteps warning present, no errors
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

        It 'Does not flag a script with no New-Step calls' {
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    s.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'Write-Host "no steps here"'
            )
            $result = Test-StepperScript -ScriptPath $path
            $result.Issues | Where-Object Code -EQ 'MissingStartStepper' | Should -BeNullOrEmpty
        }
    }
}
