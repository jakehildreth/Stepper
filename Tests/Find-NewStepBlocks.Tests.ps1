BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
}

Describe 'Find-NewStepBlocks' -Tag 'Unit' {
    Context 'When script is empty' {
        It 'Should return empty NewStepBlocks and StopStepperLine -1' {
            $result = Find-NewStepBlocks -ScriptLines @()
            $result.NewStepBlocks | Should -HaveCount 0
            $result.StopStepperLine | Should -Be -1
        }
    }

    Context 'When script has a single unnamed New-Step block' {
        BeforeAll {
            $script:lines = @(
                'New-Step {',
                '    Write-Host "step"',
                '}'
            )
        }

        It 'Should correctly identify Start and End indices' {
            $result = Find-NewStepBlocks -ScriptLines $script:lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It 'Should return StopStepperLine -1 when no Stop-Stepper present' {
            $result = Find-NewStepBlocks -ScriptLines $script:lines
            $result.StopStepperLine | Should -Be -1
        }
    }

    Context 'When script has multiple sequential New-Step blocks' {
        It 'Should correctly identify all block Start and End indices' {
            $lines = @(
                'New-Step {',
                '    Write-Host "step1"',
                '}',
                'New-Step {',
                '    Write-Host "step2"',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 2
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
            $result.NewStepBlocks[1].Start | Should -Be 3
            $result.NewStepBlocks[1].End | Should -Be 5
        }
    }

    Context 'When script contains Stop-Stepper' {
        It 'Should identify the Stop-Stepper line number' {
            $lines = @(
                'New-Step {',
                '    Write-Host "step"',
                '}',
                'Stop-Stepper'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.StopStepperLine | Should -Be 3
        }

        It 'Should stop scanning and ignore New-Step blocks after Stop-Stepper' {
            $lines = @(
                'New-Step {',
                '    Write-Host "step1"',
                '}',
                'Stop-Stepper',
                'New-Step {',
                '    Write-Host "step2"',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.StopStepperLine | Should -Be 3
        }
    }

    Context 'When New-Step uses named step syntax' {
        It "Should handle single-quoted name: New-Step 'Name' {" {
            $lines = @(
                "New-Step 'Install packages' {",
                '    Write-Host "installing"',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It 'Should handle double-quoted name: New-Step "Name" {' {
            $lines = @(
                'New-Step "Build output" {',
                '    Write-Host "building"',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It "Should handle -Name parameter: New-Step -Name 'Name' {" {
            $lines = @(
                "New-Step -Name 'Deploy app' {",
                '    Write-Host "deploying"',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }
    }

    Context 'When New-Step block contains nested braces' {
        It 'Should resolve End to the outermost closing brace' {
            $lines = @(
                'New-Step {',
                '    if ($true) {',
                '        Write-Host "nested"',
                '    }',
                '}'
            )
            $result = Find-NewStepBlocks -ScriptLines $lines
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 4
        }
    }
}
