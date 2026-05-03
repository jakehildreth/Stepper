BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/New-StepperBackup.ps1"
    . "$ModulePath/Private/Add-StepperCbh.ps1"

    function New-TempScript {
        param([string[]]$Lines)
        $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $Lines -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
        return $path
    }
}

AfterAll {
    # Temp files cleaned up per-test in AfterEach where created
}

Describe 'Add-StepperCbh' -Tag 'Unit' {

    Context 'When the script has no CBH' {
        It 'Should insert a full CBH block and return $true' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "hello" }'
                'Stop-Stepper'
            )

            try {
                # Act
                $result = Add-StepperCbh -ScriptPath $path

                # Assert
                $result | Should -BeTrue
                $content = Get-Content -Path $path -Raw
                $content | Should -Match '\.SYNOPSIS'
                $content | Should -Match '\.DESCRIPTION'
                $content | Should -Match '\.NOTES'
                $content | Should -Match 'Stepper'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }

        It 'Should place the CBH block before [CmdletBinding()]' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act
                Add-StepperCbh -ScriptPath $path

                # Assert
                $content = Get-Content -Path $path -Raw
                $cbhIndex = $content.IndexOf('<#')
                $cbIndex  = $content.IndexOf('[CmdletBinding()]')
                $cbhIndex | Should -BeLessThan $cbIndex
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'When a CBH block exists but has no .NOTES section' {
        It 'Should append a .NOTES section and return $true' {
            # Arrange
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    My deployment script.'
                '.DESCRIPTION'
                '    Deploys things to places.'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act
                $result = Add-StepperCbh -ScriptPath $path

                # Assert
                $result | Should -BeTrue
                $content = Get-Content -Path $path -Raw
                $content | Should -Match '\.NOTES'
                $content | Should -Match 'Stepper'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'When a .NOTES section exists without the Stepper blurb' {
        It 'Should append the Stepper usage blurb and return $true' {
            # Arrange
            $path = New-TempScript @(
                '<#'
                '.SYNOPSIS'
                '    My script.'
                '.NOTES'
                '    Author: Jake'
                '#>'
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act
                $result = Add-StepperCbh -ScriptPath $path

                # Assert
                $result | Should -BeTrue
                $content = Get-Content -Path $path -Raw
                $notesIdx  = $content.IndexOf('.NOTES')
                $stepperIdx = $content.IndexOf('Stepper', $notesIdx)
                $stepperIdx | Should -BeGreaterThan $notesIdx
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'When the Stepper blurb is already present in .NOTES' {
        It 'Should return $false and not modify the file' {
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
                'Stop-Stepper'
            )

            try {
                $before = Get-Content -Path $path -Raw

                # Act
                $result = Add-StepperCbh -ScriptPath $path

                # Assert
                $result | Should -BeFalse
                $after = Get-Content -Path $path -Raw
                $after | Should -Be $before
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Silent behavior' {
        It 'Should not call Write-Host' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act / Assert
                Mock Write-Host { }

                Add-StepperCbh -ScriptPath $path

                Should -Invoke Write-Host -Times 0 -Exactly
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }

        It 'Should not call exit' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act / Assert — if exit is called Pester would catch an ExitException
                { Add-StepperCbh -ScriptPath $path } | Should -Not -Throw
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Return value' {
        It 'Should return a boolean (not write to pipeline accidentally)' {
            # Arrange
            $path = New-TempScript @(
                '[CmdletBinding()]'
                'param()'
                'Stop-Stepper'
            )

            try {
                # Act
                $result = Add-StepperCbh -ScriptPath $path

                # Assert
                $result | Should -BeOfType [bool]
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
            }
        }
    }
}
