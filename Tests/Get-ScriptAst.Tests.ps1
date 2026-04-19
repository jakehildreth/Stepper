BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
}

Describe 'Get-ScriptAst' -Tag 'Unit' {
    Context 'When given a valid script file' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "valid-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                '#requires -Modules Stepper'
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $script:Result = Get-ScriptAst -ScriptPath $script:ScriptPath
        }

        It 'Should return a PSCustomObject' {
            $script:Result | Should -BeOfType [PSCustomObject]
        }

        It 'Should populate the Ast property' {
            $script:Result.Ast | Should -Not -BeNullOrEmpty
        }

        It 'Should populate the Tokens property' {
            $script:Result.Tokens | Should -Not -BeNullOrEmpty
        }

        It 'Should populate the Errors property (empty for valid script)' {
            $script:Result.Errors | Should -HaveCount 0
        }

        It 'Should return a ScriptBlockAst as the Ast' {
            $script:Result.Ast | Should -BeOfType [System.Management.Automation.Language.ScriptBlockAst]
        }
    }

    Context 'When called twice for the same unmodified file (cache hit)' {
        BeforeAll {
            $script:CachePath = Join-Path $TestDrive "cache-$(New-Guid).ps1"
            Set-Content -Path $script:CachePath -Value 'Write-Host "hello"'
            $script:First  = Get-ScriptAst -ScriptPath $script:CachePath
            $script:Second = Get-ScriptAst -ScriptPath $script:CachePath
        }

        It 'Should return the same Ast object reference on second call' {
            $script:Second.Ast | Should -Be $script:First.Ast
        }
    }

    Context 'When script file has a parse error' {
        BeforeAll {
            $script:BadPath = Join-Path $TestDrive "bad-$(New-Guid).ps1"
            Set-Content -Path $script:BadPath -Value 'function { }'
        }

        It 'Should still return a result (partial AST)' {
            $result = Get-ScriptAst -ScriptPath $script:BadPath
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should populate the Errors property' {
            $result = Get-ScriptAst -ScriptPath $script:BadPath
            $result.Errors.Count | Should -BeGreaterThan 0
        }

        It 'Should emit a warning per parse error' {
            # Use a fresh unique path to avoid cache hit (cached results skip Write-Warning)
            $freshBadPath = Join-Path $TestDrive "bad-warn-$(New-Guid).ps1"
            Set-Content -Path $freshBadPath -Value 'function { }'
            { Get-ScriptAst -ScriptPath $freshBadPath -WarningAction Stop } |
                Should -Throw
        }
    }

    Context 'When script file does not exist' {
        It 'Should throw' {
            { Get-ScriptAst -ScriptPath (Join-Path $TestDrive 'nonexistent.ps1') } |
                Should -Throw
        }
    }
}
