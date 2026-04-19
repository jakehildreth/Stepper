BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Test-StepperScriptRequirements.ps1"
}

Describe 'Test-StepperScriptRequirements' -Tag 'Unit' {
    BeforeAll {
        Mock Write-Host {}
        Mock Read-Host { 'S' }
    }

    Context 'When script already has both declarations' {
        BeforeEach {
            $script:ScriptPath = Join-Path $TestDrive "complete-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                '#requires -Modules Stepper'
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
        }

        It 'Should return $false' {
            $result = Test-StepperScriptRequirements -ScriptPath $script:ScriptPath
            $result | Should -BeFalse
        }

        It 'Should not prompt the user' {
            Test-StepperScriptRequirements -ScriptPath $script:ScriptPath
            Should -Invoke Read-Host -Exactly 0 -Scope It
        }
    }

    Context 'When [CmdletBinding()] is missing' {
        It 'Should prompt the user' {
            $scriptPath = Join-Path $TestDrive "missing-cb-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '#requires -Modules Stepper'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            Should -Invoke Read-Host -Exactly 1 -Scope It
        }
    }

    Context 'When #requires -Modules Stepper is missing' {
        It 'Should prompt the user' {
            $scriptPath = Join-Path $TestDrive "missing-req-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            Should -Invoke Read-Host -Exactly 1 -Scope It
        }
    }

    Context 'When user chooses A (add declarations)' {
        BeforeAll {
            Mock Read-Host { 'A' }
            $script:AddPath = Join-Path $TestDrive "add-a-$(New-Guid).ps1"
            Set-Content -Path $script:AddPath -Value @(
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $script:AddResult = Test-StepperScriptRequirements -ScriptPath $script:AddPath
            $script:AddContent = Get-Content -Path $script:AddPath -Raw
        }

        It 'Should return $true' {
            $script:AddResult | Should -BeTrue
        }

        It 'Should add #requires -Modules Stepper to the file' {
            $script:AddContent | Should -Match '(?i)#requires\s+-Modules?\s+Stepper'
        }

        It 'Should add [CmdletBinding()] to the file' {
            $script:AddContent | Should -Match '\[CmdletBinding\(\)\]'
        }
    }

    Context 'When user chooses S (skip)' {
        It 'Should return $false' {
            $scriptPath = Join-Path $TestDrive "skip-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $result = Test-StepperScriptRequirements -ScriptPath $scriptPath
            $result | Should -BeFalse
        }

        It 'Should leave the file unmodified' {
            $scriptPath = Join-Path $TestDrive "skip-hash-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $originalHash = (Get-FileHash -Path $scriptPath).Hash
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            (Get-FileHash -Path $scriptPath).Hash | Should -Be $originalHash
        }
    }

    Context 'When script starts with a shebang and comments' {
        It 'Should insert declarations after shebang and comments, before first code' {
            $scriptPath = Join-Path $TestDrive "shebang-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '#!/usr/bin/env pwsh'
                '# My script comment'
                ''
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Mock Read-Host { 'A' }
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $lines = Get-Content -Path $scriptPath
            $commentIdx = [array]::IndexOf($lines, '# My script comment')
            $requiresIdx = ($lines | Select-String '(?i)#requires').LineNumber - 1
            $stepIdx = [array]::IndexOf($lines, 'New-Step { Write-Host "step" }')
            $requiresIdx | Should -BeGreaterThan $commentIdx
            $requiresIdx | Should -BeLessThan $stepIdx
        }
    }

    Context 'When script already has a param() block' {
        It 'Should not duplicate param()' {
            $scriptPath = Join-Path $TestDrive "has-param-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '#requires -Modules Stepper'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Mock Read-Host { 'A' }
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $lines = Get-Content -Path $scriptPath
            $paramCount = ($lines | Where-Object { $_ -match '^\s*param\s*\(\s*\)\s*$' }).Count
            $paramCount | Should -Be 1
        }
    }

    Context 'When #requires uses different casing or -Module (singular)' {
        It 'Should recognize #Requires -Module Stepper as satisfying the requirement' {
            $scriptPath = Join-Path $TestDrive "requires-case-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '#Requires -Module Stepper'
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $result = Test-StepperScriptRequirements -ScriptPath $scriptPath
            $result | Should -BeFalse
        }
    }

    Context 'When declarations are added and a state file exists' {
        It 'Should delete the state file' {
            $scriptPath = Join-Path $TestDrive "state-delete-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $statePath = Get-StepperStatePath -ScriptPath $scriptPath
            Set-Content -Path $statePath -Value 'dummy state'
            Mock Read-Host { 'A' }
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $statePath | Should -Not -Exist
        }
    }
}
