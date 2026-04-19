BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-StepLogConfig.ps1"

    # Helper: write a temporary script file and return its path
    function New-TempScript {
        param([string[]]$Lines)
        $path = Join-Path $TestDrive "script-$(New-Guid).ps1"
        Set-Content -Path $path -Value $Lines
        return $path
    }
}

Describe 'Get-StepLogConfig' -Tag 'Unit' {
    Context 'No logging parameters on any step' {
        It 'Should return empty UniqueStaticLogPaths when no -LogPath is used' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                "New-Step 'Step 2' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths | Should -BeNullOrEmpty
        }

        It 'Should return HasConflict = $false when no -LogPath is used' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.HasConflict | Should -BeFalse
        }

        It 'Should return empty NoLogStepIds when no -NoLog is used' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.NoLogStepIds | Should -BeNullOrEmpty
        }
    }

    Context 'Single static -LogPath on one step' {
        It 'Should return the path in UniqueStaticLogPaths' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -LogPath 'C:\logs\run.log' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths | Should -Contain 'C:\logs\run.log'
        }

        It 'Should return HasConflict = $false with a single path' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -LogPath 'C:\logs\run.log' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.HasConflict | Should -BeFalse
        }

        It 'Should return exactly one entry in UniqueStaticLogPaths' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -LogPath 'C:\logs\run.log' { }"
                "New-Step 'Step 2' -LogPath 'C:\logs\run.log' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths.Count | Should -Be 1
        }
    }

    Context 'Conflicting static -LogPath values' {
        It 'Should return HasConflict = $true when two different paths are specified' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -LogPath 'C:\logs\a.log' { }"
                "New-Step 'Step 2' -LogPath 'C:\logs\b.log' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.HasConflict | Should -BeTrue
        }

        It 'Should return both paths in UniqueStaticLogPaths' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -LogPath 'C:\logs\a.log' { }"
                "New-Step 'Step 2' -LogPath 'C:\logs\b.log' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths | Should -Contain 'C:\logs\a.log'
            $result.UniqueStaticLogPaths | Should -Contain 'C:\logs\b.log'
        }
    }

    Context 'Dynamic -LogPath (variable argument)' {
        It 'Should record <dynamic> for a variable argument' {
            $path = New-TempScript @(
                '$myLog = "C:\logs\run.log"'
                "New-Step 'Step 1' -LogPath `$myLog { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths | Should -Contain '<dynamic>'
        }

        It 'Should not flag HasConflict for a single dynamic path' {
            $path = New-TempScript @(
                '$myLog = "C:\logs\run.log"'
                "New-Step 'Step 1' -LogPath `$myLog { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.HasConflict | Should -BeFalse
        }
    }

    Context '-NoLog switch detection' {
        It 'Should return the step ID in NoLogStepIds when -NoLog is present' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -NoLog { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.NoLogStepIds | Should -Not -BeNullOrEmpty
        }

        It 'Should return the correct step line number in NoLogStepIds' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                "New-Step 'Step 2' -NoLog { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            # Line 2 is the -NoLog step (1-based)
            $result.NoLogStepIds | Should -Match ':2$'
        }

        It 'Should not include steps without -NoLog in NoLogStepIds' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                "New-Step 'Step 2' -NoLog { }"
                "New-Step 'Step 3' { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.NoLogStepIds.Count | Should -Be 1
        }

        It 'Should return multiple step IDs when multiple steps have -NoLog' {
            $path = New-TempScript @(
                "New-Step 'Step 1' -NoLog { }"
                "New-Step 'Step 2' -NoLog { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.NoLogStepIds.Count | Should -Be 2
        }
    }

    Context 'Steps after Stop-Stepper are excluded' {
        It 'Should not detect -NoLog on a step after Stop-Stepper' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                'Stop-Stepper'
                "New-Step 'After stop' -NoLog { }"
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.NoLogStepIds | Should -BeNullOrEmpty
        }

        It 'Should not detect -LogPath on a step after Stop-Stepper' {
            $path = New-TempScript @(
                "New-Step 'Step 1' { }"
                'Stop-Stepper'
                "New-Step 'After stop' -LogPath 'C:\logs\run.log' { }"
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.UniqueStaticLogPaths | Should -BeNullOrEmpty
        }
    }

    Context 'Return type' {
        It 'Should return a PSCustomObject' {
            $path = New-TempScript @(
                "New-Step { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should have UniqueStaticLogPaths property' {
            $path = New-TempScript @(
                "New-Step { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.PSObject.Properties.Name | Should -Contain 'UniqueStaticLogPaths'
        }

        It 'Should have HasConflict property' {
            $path = New-TempScript @(
                "New-Step { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.PSObject.Properties.Name | Should -Contain 'HasConflict'
        }

        It 'Should have NoLogStepIds property' {
            $path = New-TempScript @(
                "New-Step { }"
                'Stop-Stepper'
            )
            $result = Get-StepLogConfig -ScriptPath $path
            $result.PSObject.Properties.Name | Should -Contain 'NoLogStepIds'
        }
    }
}
