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
        Mock Read-Host {}
        Mock Write-Verbose {}
    }

    Context 'When script already has [CmdletBinding()]' {
        BeforeEach {
            $script:ScriptPath = Join-Path $TestDrive "complete-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
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

        It 'Should not call Read-Host' {
            Test-StepperScriptRequirements -ScriptPath $script:ScriptPath
            Should -Invoke Read-Host -Exactly 0 -Scope It
        }

        It 'Should not emit verbose about adding declarations' {
            Test-StepperScriptRequirements -ScriptPath $script:ScriptPath
            Should -Invoke Write-Verbose -Exactly 0 -Scope It -ParameterFilter { $Message -match 'Added missing' }
        }
    }

    Context 'When [CmdletBinding()] is missing' {
        BeforeEach {
            $script:CbMissingPath = Join-Path $TestDrive "missing-cb-$(New-Guid).ps1"
            Set-Content -Path $script:CbMissingPath -Value @(
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
        }

        It 'Should return $true' {
            $result = Test-StepperScriptRequirements -ScriptPath $script:CbMissingPath
            $result | Should -BeTrue
        }

        It 'Should add [CmdletBinding()] to the file' {
            Test-StepperScriptRequirements -ScriptPath $script:CbMissingPath
            $content = Get-Content -Path $script:CbMissingPath -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]'
        }

        It 'Should add Install-Module guard to the file' {
            Test-StepperScriptRequirements -ScriptPath $script:CbMissingPath
            $content = Get-Content -Path $script:CbMissingPath -Raw
            $content | Should -Match 'Install-Module Stepper'
        }

        It 'Should emit Write-Verbose reporting the addition' {
            Test-StepperScriptRequirements -ScriptPath $script:CbMissingPath
            Should -Invoke Write-Verbose -Scope It
        }

        It 'Should not call Read-Host' {
            Test-StepperScriptRequirements -ScriptPath $script:CbMissingPath
            Should -Invoke Read-Host -Exactly 0 -Scope It
        }
    }

    Context 'When #requires -Modules Stepper is missing' {
        It 'Should return $false (only [CmdletBinding()] is checked)' {
            $scriptPath = Join-Path $TestDrive "missing-req-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $result = Test-StepperScriptRequirements -ScriptPath $scriptPath
            $result | Should -BeFalse
        }
    }

    Context 'When [CmdletBinding()] is missing (no declarations at all)' {
        BeforeEach {
            $script:MissingBothPath = Join-Path $TestDrive "both-missing-$(New-Guid).ps1"
            Set-Content -Path $script:MissingBothPath -Value @(
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
        }

        It 'Should return $true' {
            $result = Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            $result | Should -BeTrue
        }

        It 'Should add [CmdletBinding()] to the file' {
            Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            $content = Get-Content -Path $script:MissingBothPath -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]'
        }

        It 'Should add Install-Module guard to the file' {
            Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            $content = Get-Content -Path $script:MissingBothPath -Raw
            $content | Should -Match 'Install-Module Stepper'
        }

        It 'Should not add #requires to the file' {
            Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            $content = Get-Content -Path $script:MissingBothPath -Raw
            $content | Should -Not -Match '(?i)#requires'
        }

        It 'Should emit Write-Verbose reporting the addition' {
            Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            Should -Invoke Write-Verbose -Scope It
        }

        It 'Should not call Read-Host' {
            Test-StepperScriptRequirements -ScriptPath $script:MissingBothPath
            Should -Invoke Read-Host -Exactly 0 -Scope It
        }
    }

    Context 'When script starts with a shebang and comments' {
        It 'Should insert [CmdletBinding()] after shebang and comments, before first code' {
            $scriptPath = Join-Path $TestDrive "shebang-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                '#!/usr/bin/env pwsh'
                '# My script comment'
                ''
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $lines = Get-Content -Path $scriptPath
            $commentIdx = [array]::IndexOf($lines, '# My script comment')
            $cmdletIdx  = ($lines | Select-String '\[CmdletBinding').LineNumber - 1
            $stepIdx    = [array]::IndexOf($lines, 'New-Step { Write-Host "step" }')
            $cmdletIdx | Should -BeGreaterThan $commentIdx
            $cmdletIdx | Should -BeLessThan $stepIdx
        }
    }

    Context 'When script already has a param() block' {
        It 'Should not duplicate param()' {
            $scriptPath = Join-Path $TestDrive "has-param-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $lines = Get-Content -Path $scriptPath
            $paramCount = ($lines | Where-Object { $_ -match '^\s*param\s*\(\s*\)\s*$' }).Count
            $paramCount | Should -Be 1
        }
    }

    Context 'When #requires uses different casing or -Module (singular)' {
        It 'Should return $false (Stepper does not check for #requires)' {
            $scriptPath = Join-Path $TestDrive "requires-case-$(New-Guid).ps1"
            Set-Content -Path $scriptPath -Value @(
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
            Test-StepperScriptRequirements -ScriptPath $scriptPath
            $statePath | Should -Not -Exist
        }
    }
}
