BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Find-CrossStepVariables.ps1"
    . "$ModulePath/Public/ConvertTo-StepperScript.ps1"

    function New-TempScript {
        param([string[]]$Lines)
        $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $Lines -join [System.Environment]::NewLine | Set-Content -Path $path -Encoding UTF8 -NoNewline
        return $path
    }

    $CrossStepScript = @(
        '[CmdletBinding()]'
        'param()'
        'New-Step {'
        '    $servers = Get-Content servers.txt'
        '    $count = $servers.Count'
        '}'
        'New-Step {'
        '    foreach ($s in $servers) { Write-Host $s }'
        '    Write-Host "Total: $count"'
        '}'
        'Stop-Stepper'
    ) -join [System.Environment]::NewLine

    $NoCanidatesScript = @(
        '[CmdletBinding()]'
        'param()'
        'New-Step {'
        '    Write-Host "step 1"'
        '}'
        'New-Step {'
        '    Write-Host "step 2"'
        '}'
        'Stop-Stepper'
    ) -join [System.Environment]::NewLine
}

Describe 'ConvertTo-StepperScript' -Tag 'Unit' {

    Context 'Parameter binding' {
        It 'Should accept -Path (ByPath parameter set)' {
            $path = New-TempScript @('[CmdletBinding()]', 'param()', 'Stop-Stepper')
            try {
                { ConvertTo-StepperScript -Path $path -Force } | Should -Not -Throw
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should accept -Name and -Directory (ByName parameter set)' {
            $dir = [System.IO.Path]::GetTempPath()
            $name = "stepper-test-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').ps1"
            $path = Join-Path $dir $name
            Set-Content -Path $path -Value ('[CmdletBinding()]', 'param()', 'Stop-Stepper' -join [System.Environment]::NewLine) -Encoding UTF8
            try {
                { ConvertTo-StepperScript -Name $name -Directory $dir -Force } | Should -Not -Throw
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should default -Directory to $PWD when not specified' {
            $dir = [System.IO.Path]::GetTempPath()
            $name = "stepper-test-$([System.Guid]::NewGuid().ToString('N')[0..7] -join '').ps1"
            $path = Join-Path $dir $name
            Set-Content -Path $path -Value ('[CmdletBinding()]', 'param()', 'Stop-Stepper' -join [System.Environment]::NewLine) -Encoding UTF8
            Push-Location $dir
            try {
                { ConvertTo-StepperScript -Name $name -Force } | Should -Not -Throw
            }
            finally {
                Pop-Location
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'When no cross-step variable candidates exist' {
        It 'Should not modify the file' {
            $path = New-TempScript ($NoCanidatesScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            try {
                ConvertTo-StepperScript -Path $path -Force
                $newContent = Get-Content -Path $path -Raw
                $newContent | Should -Be $originalContent
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should not create a .bak file' {
            $path = New-TempScript ($NoCanidatesScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                Test-Path "$path.bak" | Should -Be $false
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Rewriting with -Force (skips interactive prompts)' {
        It 'Should rewrite cross-step variables inside New-Step bodies' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match '\$Stepper\.Servers'
                $result | Should -Match '\$Stepper\.Count'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should preserve the original assignment (write side) in the rewrite' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                # Assignment left-hand sides should also be rewritten
                $result | Should -Match '\$Stepper\.Servers\s*='
                $result | Should -Match '\$Stepper\.Count\s*='
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should NOT rewrite variables outside New-Step bodies' {
            $scriptWithOuterVar = @(
                '[CmdletBinding()]'
                'param()'
                '$servers = @("pre-step")'
                'New-Step {'
                '    $servers = Get-Content servers.txt'
                '}'
                'New-Step {'
                '    foreach ($s in $servers) { Write-Host $s }'
                '}'
                'Write-Host $servers'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($scriptWithOuterVar -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $lines = Get-Content -Path $path
                # outer assignment before first New-Step must remain plain $servers
                $lines[2] | Should -Match '^\$servers\s*='
                # last Write-Host must remain plain $servers
                $lines[-2] | Should -Match 'Write-Host \$servers'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should create a .bak backup of the original' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            try {
                ConvertTo-StepperScript -Path $path -Force
                Test-Path "$path.bak" | Should -Be $true
                Get-Content -Path "$path.bak" -Raw | Should -Be $originalContent
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should produce valid parseable PowerShell after rewrite' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
                $errors | Should -HaveCount 0
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-OutputPath behaviour' {
        It 'Should write rewritten content to -OutputPath and not modify the source' {
            $src = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $out = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            $originalContent = Get-Content -Path $src -Raw
            try {
                ConvertTo-StepperScript -Path $src -OutputPath $out -Force
                Get-Content -Path $src -Raw | Should -Be $originalContent
                $outContent = Get-Content -Path $out -Raw
                $outContent | Should -Match '\$Stepper\.'
            }
            finally {
                Remove-Item $src -ErrorAction SilentlyContinue
                Remove-Item $out -ErrorAction SilentlyContinue
            }
        }

        It 'Should not create a .bak when -OutputPath is provided' {
            $src = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $out = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            try {
                ConvertTo-StepperScript -Path $src -OutputPath $out -Force
                Test-Path "$src.bak" | Should -Be $false
            }
            finally {
                Remove-Item $src -ErrorAction SilentlyContinue
                Remove-Item $out -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'SupportsShouldProcess (-WhatIf)' {
        It 'Should not modify any file when -WhatIf is passed' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            try {
                ConvertTo-StepperScript -Path $path -Force -WhatIf
                Get-Content -Path $path -Raw | Should -Be $originalContent
                Test-Path "$path.bak" | Should -Be $false
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Variable name capitalisation in $Stepper.<Var>' {
        It 'Should capitalise the first letter of the variable name' {
            $content = @(
                '[CmdletBinding()]'
                'param()'
                'New-Step {'
                '    $myVar = 42'
                '}'
                'New-Step {'
                '    Write-Host $myVar'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($content -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match '\$Stepper\.MyVar'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }
    }
}
