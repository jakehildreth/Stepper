BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Add-StepperCbh.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"
    . "$ModulePath/Public/Repair-StepperScript.ps1"

    function New-TempScript {
        param([string[]]$Lines)
        $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $Lines -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
        return $path
    }
}

Describe 'Repair-StepperScript' -Tag 'Unit' {

    Context 'Return value' {
        It 'Should accept -Path as an alias for -ScriptPath' {
            # Arrange
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                # Act / Assert — should not throw ParameterNotFound
                { Repair-StepperScript -Path $path } | Should -Not -Throw
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should return a PSCustomObject with Path, IsValid, Issues' {
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
                $result = Repair-StepperScript -ScriptPath $path
                # Assert
                $result.PSObject.Properties.Name | Should -Contain 'Path'
                $result.PSObject.Properties.Name | Should -Contain 'IsValid'
                $result.PSObject.Properties.Name | Should -Contain 'Issues'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should return the post-fix Test-StepperScript result' {
            # Arrange — script is missing CmdletBinding
            $path = New-TempScript @(
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Repair-StepperScript -ScriptPath $path
                # Assert — after repair, MissingCmdletBinding should be gone
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Not -Contain 'MissingCmdletBinding'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Fixing MissingCmdletBinding' {
        It 'Should add [CmdletBinding()] when missing' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                Repair-StepperScript -ScriptPath $path | Out-Null
                # Assert
                $content = Get-Content -Path $path -Raw
                $content | Should -Match '\[CmdletBinding\(\)\]'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Fixing MissingInstallGuard' {
        It 'Should add Install-Module Stepper guard when missing' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                # Act
                Repair-StepperScript -ScriptPath $path | Out-Null
                # Assert
                $content = Get-Content -Path $path -Raw
                $content | Should -Match 'Install-Module\s+Stepper'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Fixing MissingCbh' {
        It 'Should add CBH when missing (via Add-StepperCbh)' {
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
                Repair-StepperScript -ScriptPath $path | Out-Null
                # Assert
                $content = Get-Content -Path $path -Raw
                $content | Should -Match '\.SYNOPSIS'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Warning-only issues are reported not fixed' {
        It 'Should not add Stop-Stepper for MissingStopStepper' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'New-Step { Write-Host "hi" }'
            )
            try {
                $before = Get-Content -Path $path -Raw
                # Act
                $result = Repair-StepperScript -ScriptPath $path
                $after  = Get-Content -Path $path -Raw
                # Assert — file should not have Stop-Stepper injected by Repair
                $after | Should -Not -Match 'Stop-Stepper'
                # but the issue should still be in the result
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'MissingStopStepper'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should not inject New-Step blocks for NoSteps' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'if (-not (Get-Module Stepper)) { Install-Module Stepper -Force }'
                'Stop-Stepper'
            )
            try {
                # Act
                $result = Repair-StepperScript -ScriptPath $path
                $content = Get-Content -Path $path -Raw
                # Assert — no actual New-Step { } call injected (CBH blurb may mention it)
                $content | Should -Not -Match 'New-Step\s*\{'
                $codes = $result.Issues | Select-Object -ExpandProperty Code
                $codes | Should -Contain 'NoSteps'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Already-valid script' {
        It 'Should return IsValid = $true and not modify the file' {
            # Arrange
            $path = New-TempScript @(
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
                '#endregion Stepper ignore'
                'New-Step { Write-Host "step 1" }'
                'Stop-Stepper'
            )
            try {
                $before = Get-Content -Path $path -Raw
                # Act
                $result = Repair-StepperScript -ScriptPath $path
                $after  = Get-Content -Path $path -Raw
                # Assert
                $result.IsValid | Should -BeTrue
                $after | Should -Be $before
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'SupportsShouldProcess (-WhatIf)' {
        It 'Should not modify the file when -WhatIf is passed' {
            # Arrange
            $path = New-TempScript @(
                'param()'
                'New-Step { Write-Host "hi" }'
                'Stop-Stepper'
            )
            try {
                $before = Get-Content -Path $path -Raw
                # Act
                Repair-StepperScript -ScriptPath $path -WhatIf
                $after = Get-Content -Path $path -Raw
                # Assert
                $after | Should -Be $before
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }
}
