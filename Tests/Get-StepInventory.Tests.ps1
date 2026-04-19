BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepInventory.ps1"
}

Describe 'Get-StepInventory' -Tag 'Unit' {
    Context 'When script has no New-Step calls' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "no-steps-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value 'Write-Host "no steps here"'
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should return TotalSteps of 0' {
            $script:Result.TotalSteps | Should -Be 0
        }

        It 'Should return empty StepLines' {
            $script:Result.StepLines | Should -HaveCount 0
        }

        It 'Should return empty StepNames' {
            $script:Result.StepNames | Should -HaveCount 0
        }
    }

    Context 'When script has a single unnamed New-Step' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "one-step-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                'New-Step {'
                '    Write-Host "step"'
                '}'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should return TotalSteps of 1' {
            $script:Result.TotalSteps | Should -Be 1
        }

        It 'Should return a StepLine in path:line format' {
            $script:Result.StepLines[0] | Should -Match '^.+:\d+$'
        }

        It 'Should return $null for the step name' {
            $script:Result.StepNames[0] | Should -BeNullOrEmpty
        }
    }

    Context 'When script has multiple unnamed steps' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "multi-steps-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                'New-Step { Write-Host "step1" }'
                'New-Step { Write-Host "step2" }'
                'New-Step { Write-Host "step3" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should return TotalSteps of 3' {
            $script:Result.TotalSteps | Should -Be 3
        }

        It 'Should return StepLines in ascending line order' {
            $lineNums = $script:Result.StepLines | ForEach-Object { [int]($_ -split ':')[-1] }
            $lineNums | Should -Be @(1, 2, 3)
        }
    }

    Context 'When script has single-quoted named steps' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "named-sq-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                "New-Step 'Install packages' { Write-Host 'step1' }"
                "New-Step 'Deploy app' { Write-Host 'step2' }"
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should return TotalSteps of 2' {
            $script:Result.TotalSteps | Should -Be 2
        }

        It 'Should capture first step name' {
            $script:Result.StepNames[0] | Should -Be 'Install packages'
        }

        It 'Should capture second step name' {
            $script:Result.StepNames[1] | Should -Be 'Deploy app'
        }
    }

    Context 'When script has double-quoted named steps' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "named-dq-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                'New-Step "Build output" { Write-Host "step" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should capture the step name' {
            $script:Result.StepNames[0] | Should -Be 'Build output'
        }
    }

    Context 'When script uses -Name parameter syntax' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "named-param-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                "New-Step -Name 'Verify prereqs' { Write-Host 'step' }"
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should capture the step name' {
            $script:Result.StepNames[0] | Should -Be 'Verify prereqs'
        }
    }

    Context 'When script has Stop-Stepper' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "with-stop-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                'New-Step { Write-Host "step1" }'
                'New-Step { Write-Host "step2" }'
                'Stop-Stepper'
                'New-Step { Write-Host "after stop" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should exclude steps after Stop-Stepper' {
            $script:Result.TotalSteps | Should -Be 2
        }

        It 'Should include steps before Stop-Stepper' {
            $lineNums = $script:Result.StepLines | ForEach-Object { [int]($_ -split ':')[-1] }
            $lineNums | Should -Be @(1, 2)
        }
    }

    Context 'When New-Step appears inside a string literal' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "in-string-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                '$msg = "Use New-Step to define steps"'
                'New-Step { Write-Host "real step" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should count only the real New-Step call' {
            $script:Result.TotalSteps | Should -Be 1
        }
    }

    Context 'When New-Step appears inside a comment' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "in-comment-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                '# New-Step would go here'
                'New-Step { Write-Host "real step" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should count only the real New-Step call' {
            $script:Result.TotalSteps | Should -Be 1
        }
    }

    Context 'StepLines format matches Get-StepIdentifier output' {
        BeforeAll {
            $script:ScriptPath = Join-Path $TestDrive "format-$(New-Guid).ps1"
            Set-Content -Path $script:ScriptPath -Value @(
                'New-Step { Write-Host "step" }'
            )
            $script:Result = Get-StepInventory -ScriptPath $script:ScriptPath
        }

        It 'Should embed the ScriptPath in each StepLine' {
            $script:Result.StepLines[0] | Should -BeLike "$($script:ScriptPath)*"
        }

        It 'Should suffix the ScriptPath with a colon and 1-based line number' {
            $script:Result.StepLines[0] | Should -Be "${script:ScriptPath}:1"
        }
    }
}
