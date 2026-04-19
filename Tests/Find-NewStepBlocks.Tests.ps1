BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
}

Describe 'Find-NewStepBlocks' -Tag 'Unit' {
    Context 'When script is empty' {
        It 'Should return empty NewStepBlocks and StopStepperLine -1' {
            $result = Find-NewStepBlocks -ScriptContent ''
            $result.NewStepBlocks | Should -HaveCount 0
            $result.StopStepperLine | Should -Be -1
        }
    }

    Context 'When script has a single unnamed New-Step block' {
        BeforeAll {
            $script:content = @(
                'New-Step {',
                '    Write-Host "step"',
                '}'
            ) -join [System.Environment]::NewLine
        }

        It 'Should correctly identify Start and End indices' {
            $result = Find-NewStepBlocks -ScriptContent $script:content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It 'Should return StopStepperLine -1 when no Stop-Stepper present' {
            $result = Find-NewStepBlocks -ScriptContent $script:content
            $result.StopStepperLine | Should -Be -1
        }
    }

    Context 'When script has multiple sequential New-Step blocks' {
        It 'Should correctly identify all block Start and End indices' {
            $content = @(
                'New-Step {',
                '    Write-Host "step1"',
                '}',
                'New-Step {',
                '    Write-Host "step2"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 2
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
            $result.NewStepBlocks[1].Start | Should -Be 3
            $result.NewStepBlocks[1].End | Should -Be 5
        }
    }

    Context 'When script contains Stop-Stepper' {
        It 'Should identify the Stop-Stepper line number' {
            $content = @(
                'New-Step {',
                '    Write-Host "step"',
                '}',
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.StopStepperLine | Should -Be 3
        }

        It 'Should exclude New-Step blocks that appear after Stop-Stepper' {
            $content = @(
                'New-Step {',
                '    Write-Host "step1"',
                '}',
                'Stop-Stepper',
                'New-Step {',
                '    Write-Host "step2"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.StopStepperLine | Should -Be 3
        }
    }

    Context 'When New-Step uses named step syntax' {
        It "Should handle single-quoted name: New-Step 'Name' {" {
            $content = @(
                "New-Step 'Install packages' {",
                '    Write-Host "installing"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It 'Should handle double-quoted name: New-Step "Name" {' {
            $content = @(
                'New-Step "Build output" {',
                '    Write-Host "building"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }

        It "Should handle -Name parameter: New-Step -Name 'Name' {" {
            $content = @(
                "New-Step -Name 'Deploy app' {",
                '    Write-Host "deploying"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }
    }

    Context 'When New-Step block contains nested braces' {
        It 'Should resolve End to the outermost closing brace' {
            $content = @(
                'New-Step {',
                '    if ($true) {',
                '        Write-Host "nested"',
                '    }',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 4
        }
    }

    Context 'When scriptblock is on a separate line from New-Step' {
        It 'Should still detect the block when { is on the next line' {
            $content = @(
                "New-Step 'My step'",
                '{',
                '    Write-Host "multi-line"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
        }
    }

    Context 'When the text New-Step appears inside a string literal' {
        It 'Should not count it as a step block' {
            $content = @(
                '$msg = "Use New-Step to define steps"',
                'New-Step {',
                '    Write-Host "real step"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
        }
    }

    Context 'When New-Step appears inside a comment' {
        It 'Should not count it as a step block' {
            $content = @(
                '# New-Step would go here',
                'New-Step {',
                '    Write-Host "real step"',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
        }
    }

    Context 'When a string literal contains braces' {
        It 'Should not be confused by braces inside strings' {
            $content = @(
                'New-Step {',
                '    $json = ''{"key": "value"}''',
                '}'
            ) -join [System.Environment]::NewLine
            $result = Find-NewStepBlocks -ScriptContent $content
            $result.NewStepBlocks | Should -HaveCount 1
            $result.NewStepBlocks[0].Start | Should -Be 0
            $result.NewStepBlocks[0].End | Should -Be 2
        }
    }
}
