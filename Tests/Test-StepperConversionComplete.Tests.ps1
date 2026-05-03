BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Test-StepperConversionComplete.ps1"
}

Describe 'Test-StepperConversionComplete' -Tag 'Unit' {

    Context 'When sentinel is absent' {
        It 'Should return $false for a script with no sentinel' {
            $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { Write-Host "hello" }'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
            try {
                Test-StepperConversionComplete -ScriptPath $path | Should -Be $false
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'When sentinel is present at script (top) scope' {
        It 'Should return $true when $StepperConversionComplete = $true is at top level' {
            $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            @(
                '[CmdletBinding()]'
                'param()'
                '$StepperConversionComplete = $true'
                'New-Step { Write-Host "hello" }'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
            try {
                Test-StepperConversionComplete -ScriptPath $path | Should -Be $true
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'When sentinel is only inside a New-Step body (nested scope)' {
        It 'Should return $false when assignment is inside a New-Step scriptblock' {
            $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            @(
                '[CmdletBinding()]'
                'param()'
                'New-Step {'
                '    $StepperConversionComplete = $true'
                '    Write-Host "hello"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
            try {
                Test-StepperConversionComplete -ScriptPath $path | Should -Be $false
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }
}
