BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Update-ScriptWithUnmanagedActions.ps1"
}

Describe 'Update-ScriptWithUnmanagedActions' -Tag 'Unit' {
    BeforeAll {
        Mock Write-Host {}
    }

    Context 'Wrap action' {
        It 'Should wrap a single line in a New-Step block with 4-space indent' {
            $scriptPath = Join-Path $TestDrive "wrap-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "unmanaged"',
                'New-Step {',
                '    Write-Host "step"',
                '}',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{ 0 = @{ Action = 'Wrap' } }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            $result | Should -Contain 'New-Step {'
            $result | Should -Contain '    Write-Host "unmanaged"'
            $result | Should -Contain '}'
        }
    }

    Context 'MarkIgnored action' {
        It 'Should wrap a single line in a Stepper ignore region' {
            $scriptPath = Join-Path $TestDrive "ignore-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "unmanaged"',
                'New-Step {',
                '    Write-Host "step"',
                '}',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{ 0 = @{ Action = 'MarkIgnored' } }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            $result | Should -Contain '#region Stepper ignore'
            $result | Should -Contain 'Write-Host "unmanaged"'
            $result | Should -Contain '#endregion Stepper ignore'
        }
    }

    Context 'Delete action' {
        It 'Should remove the specified line from the output' {
            $scriptPath = Join-Path $TestDrive "delete-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "remove me"',
                'New-Step {',
                '    Write-Host "step"',
                '}',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{ 0 = @{ Action = 'Delete' } }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            $result | Should -Not -Contain 'Write-Host "remove me"'
        }
    }

    Context 'Non-actioned lines' {
        It 'Should preserve non-actioned lines exactly' {
            $scriptPath = Join-Path $TestDrive "preserve-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "delete me"',
                'Write-Host "keep me exactly"',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{ 0 = @{ Action = 'Delete' } }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            $result | Should -Contain 'Write-Host "keep me exactly"'
            $result | Should -Contain 'Stop-Stepper'
        }
    }

    Context 'Consecutive lines grouped into a single block' {
        It 'Should wrap consecutive Wrap lines in a single New-Step block' {
            $scriptPath = Join-Path $TestDrive "consec-wrap-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "line0"',
                'Write-Host "line1"',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{
                0 = @{ Action = 'Wrap' }
                1 = @{ Action = 'Wrap' }
            }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            ($result | Where-Object { $_ -eq 'New-Step {' }) | Should -HaveCount 1
        }

        It 'Should wrap consecutive MarkIgnored lines in a single region block' {
            $scriptPath = Join-Path $TestDrive "consec-ignore-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "line0"',
                'Write-Host "line1"',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{
                0 = @{ Action = 'MarkIgnored' }
                1 = @{ Action = 'MarkIgnored' }
            }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            ($result | Where-Object { $_ -eq '#region Stepper ignore' }) | Should -HaveCount 1
        }
    }

    Context 'Multiple non-adjacent action groups' {
        It 'Should handle multiple non-adjacent groups correctly in one pass' {
            $scriptPath = Join-Path $TestDrive "multi-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "wrap-me"',
                'New-Step { Write-Host "step" }',
                'Write-Host "ignore-me"',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $actions = @{
                0 = @{ Action = 'Wrap' }
                2 = @{ Action = 'MarkIgnored' }
            }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $result = Get-Content -Path $scriptPath
            $result | Should -Contain 'New-Step {'
            $result | Should -Contain '    Write-Host "wrap-me"'
            $result | Should -Contain '#region Stepper ignore'
            $result | Should -Contain 'Write-Host "ignore-me"'
            $result | Should -Contain '#endregion Stepper ignore'
        }
    }

    Context 'State file cleanup' {
        It 'Should delete the state file after modifying the script' {
            $scriptPath = Join-Path $TestDrive "state-$(New-Guid).ps1"
            $lines = @(
                'Write-Host "delete me"',
                'Stop-Stepper'
            )
            Set-Content -Path $scriptPath -Value $lines
            $statePath = Get-StepperStatePath -ScriptPath $scriptPath
            Set-Content -Path $statePath -Value 'dummy state'
            $actions = @{ 0 = @{ Action = 'Delete' } }

            Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @()

            $statePath | Should -Not -Exist
        }
    }

    Context 'Write failure' {
        BeforeAll {
            Mock Set-Content { throw [System.IO.IOException]::new('disk full') }
        }

        It 'Should throw a terminating error with ScriptWriteFailed error id' {
            $scriptPath = Join-Path $TestDrive 'error.ps1'
            $lines = @('Write-Host "test"', 'Stop-Stepper')
            $actions = @{ 0 = @{ Action = 'Delete' } }

            { Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $lines -Actions $actions -NewStepBlocks @() } |
                Should -Throw -ErrorId 'ScriptWriteFailed*'
        }
    }
}
