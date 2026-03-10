BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Test-LineInIgnoredRegion.ps1"
    . "$ModulePath/Private/Find-UnmanagedCodeBlocks.ps1"
}

Describe 'Find-UnmanagedCodeBlocks' -Tag 'Unit' {
    Context 'When script has no New-Step blocks' {
        It 'Should return empty result' {
            $lines = @('Write-Host "hello"', 'Stop-Stepper')
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks @() -StopStepperLine 1
            $result | Should -HaveCount 0
        }
    }

    Context 'When all code is inside New-Step blocks' {
        It 'Should return empty result' {
            $lines = @(
                'New-Step {',
                '    Write-Host "step"',
                '}'
            )
            $blocks = @(@{ Start = 0; End = 2 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 0
        }
    }

    Context 'When there is executable code before the first New-Step block' {
        It 'Should detect unmanaged code and include its line index' {
            $lines = @(
                'Write-Host "unmanaged"',  # 0
                'New-Step {',              # 1
                '    Write-Host "step"',   # 2
                '}'                        # 3
            )
            $blocks = @(@{ Start = 1; End = 3 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 1
            (@($result)[0]).Lines | Should -Contain 0
        }
    }

    Context 'When there is executable code between two New-Step blocks' {
        It 'Should detect unmanaged code in the gap and include its line index' {
            $lines = @(
                'New-Step {',              # 0
                '    Write-Host "step1"',  # 1
                '}',                       # 2
                'Write-Host "unmanaged"',  # 3
                'New-Step {',              # 4
                '    Write-Host "step2"',  # 5
                '}'                        # 6
            )
            $blocks = @(
                @{ Start = 0; End = 2 },
                @{ Start = 4; End = 6 }
            )
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 1
            (@($result)[0]).Lines | Should -Contain 3
        }
    }

    Context 'When there is executable code between last New-Step and Stop-Stepper' {
        It 'Should detect unmanaged code and set IsBeforeStop to $true' {
            $lines = @(
                'New-Step {',              # 0
                '    Write-Host "step"',   # 1
                '}',                       # 2
                'Write-Host "unmanaged"',  # 3
                'Stop-Stepper'             # 4
            )
            $blocks = @(@{ Start = 0; End = 2 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine 4
            $result | Should -HaveCount 1
            $block = @($result)[0]
            $block.Lines | Should -Contain 3
            $block.IsBeforeStop | Should -BeTrue
        }

        It 'Should set IsBeforeStop to $false for unmanaged code before first block with no Stop-Stepper' {
            $lines = @(
                'Write-Host "unmanaged"',  # 0
                'New-Step {',              # 1
                '    Write-Host "step"',   # 2
                '}'                        # 3
            )
            $blocks = @(@{ Start = 1; End = 3 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 1
            (@($result)[0]).IsBeforeStop | Should -BeFalse
        }
    }

    Context 'When skippable lines appear before the first block' {
        It 'Should skip blank lines and comment-only lines' {
            $lines = @(
                '',                        # 0 - blank
                '# this is a comment',     # 1 - comment
                'New-Step {',              # 2
                '    Write-Host "step"',   # 3
                '}'                        # 4
            )
            $blocks = @(@{ Start = 2; End = 4 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 0
        }

        It 'Should skip [CmdletBinding()], param(), and using statements' {
            $lines = @(
                '[CmdletBinding()]',        # 0
                'param()',                  # 1
                'using module Stepper',     # 2
                'New-Step {',              # 3
                '    Write-Host "step"',   # 4
                '}'                        # 5
            )
            $blocks = @(@{ Start = 3; End = 5 })
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 0
        }
    }

    Context 'When code is inside a Stepper ignore region' {
        It 'Should skip lines inside #region Stepper ignore / #endregion Stepper ignore' {
            $lines = @(
                'New-Step {',                 # 0
                '    Write-Host "step1"',     # 1
                '}',                          # 2
                '#region Stepper ignore',     # 3
                'Write-Host "ignored"',       # 4
                '#endregion Stepper ignore',  # 5
                'New-Step {',                 # 6
                '    Write-Host "step2"',     # 7
                '}'                           # 8
            )
            $blocks = @(
                @{ Start = 0; End = 2 },
                @{ Start = 6; End = 8 }
            )
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 0
        }
    }

    Context 'When code is inside a multi-line comment block' {
        It 'Should skip lines inside PowerShell block comment regions' {
            $lines = @(
                'New-Step {',              # 0
                '    Write-Host "step1"',  # 1
                '}',                       # 2
                '<#',                      # 3
                'Write-Host "ignored"',    # 4
                '#>',                      # 5
                'New-Step {',              # 6
                '    Write-Host "step2"',  # 7
                '}'                        # 8
            )
            $blocks = @(
                @{ Start = 0; End = 2 },
                @{ Start = 6; End = 8 }
            )
            $result = Find-UnmanagedCodeBlocks -ScriptLines $lines -NewStepBlocks $blocks -StopStepperLine -1
            $result | Should -HaveCount 0
        }
    }
}
