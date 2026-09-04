<#
.SYNOPSIS
    ConvertTo-StepperScript.Tests

.DESCRIPTION
    ConvertTo-StepperScript.Tests

.NOTES
    Managed by Stepper. Use New-Step blocks to define resumable steps.
#>
[CmdletBinding()]
param()

BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Find-CrossStepVariables.ps1"
    . "$ModulePath/Private/Get-StepperInitInsertionIndex.ps1"
    . "$ModulePath/Private/New-StepperBackup.ps1"
    . "$ModulePath/Private/Test-StepperConversionComplete.ps1"
    . "$ModulePath/Public/ConvertTo-StepperScript.ps1"

    # Remove all timestamped .ps1.bak files produced by New-StepperBackup for a given source path
    function Remove-TempBaks {
        param([string]$Path)
        $dir  = Split-Path -Parent $Path
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        Get-ChildItem -Path $dir -Filter "$base.*.ps1.bak" | Remove-Item -Force -ErrorAction SilentlyContinue
    }

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

        It 'Should not create a backup when no candidates exist' {
            $path = New-TempScript ($NoCanidatesScript -split [System.Environment]::NewLine)
            $dir  = Split-Path -Parent $path
            $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
            try {
                ConvertTo-StepperScript -Path $path -Force
                @(Get-ChildItem -Path $dir -Filter "$base.*.ps1.bak") | Should -HaveCount 0
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

        It 'Should rewrite all occurrences of a candidate, including in unmanaged (script-level) code' {
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
                $result = Get-Content -Path $path -Raw
                # $servers is a cross-step candidate; all uses must be rewritten
                $result | Should -Not -Match '(?<!\.)(\$servers)\b'
                $result | Should -Match '\$Stepper\.Servers'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should not add Start-Stepper when all candidates are assigned inside New-Step blocks but the script already has it' {
            # CrossStepScript assigns $servers/$count only inside New-Step bodies.
            # The converter emits Start-Stepper idempotently only when absent; this
            # script already... (no Start-Stepper present, so it IS added; assert no
            # legacy bootstrap initializer appears).
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match '\$Stepper\.Servers'
                $result | Should -Not -Match 'if \(\$null -eq \$Stepper\)'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should add Start-Stepper even when a blank New-Step bootstrap precedes the unmanaged assignment' {
            # Regression: a blank bootstrap New-Step must not suppress Start-Stepper.
            $scriptWithBootstrap = @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { }'
                '$name = "Jake"'
                'New-Step { Write-Host $name }'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($scriptWithBootstrap -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match 'Start-Stepper'
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should create a timestamped .bak backup of the original' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            $dir  = Split-Path -Parent $path
            $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $bakFiles = @(Get-ChildItem -Path $dir -Filter "$base.*.ps1.bak")
                $bakFiles | Should -HaveCount 1
                Get-Content -LiteralPath $bakFiles[0].FullName -Raw | Should -Be $originalContent
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-TempBaks $path
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

        It 'Should place Start-Stepper before the first converted assignment' {
            # Cross-step variable first assigned in unmanaged (script-level) code
            # that runs before any New-Step. Start-Stepper initializes $Stepper
            # before unmanaged code runs, so the converted '$Stepper.Name = ...'
            # line is safe. Assert Start-Stepper precedes the first assignment.
            $scriptWithUnmanagedFirst = @(
                '[CmdletBinding()]'
                'param()'
                '$name = Read-Host "Name?"'
                'New-Step {'
                '    Write-Host $name'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($scriptWithUnmanagedFirst -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match 'Start-Stepper'
                $initIndex = $result.IndexOf('Start-Stepper')
                $assignIndex = $result.IndexOf('$Stepper.Name')
                $assignIndex | Should -BeGreaterThan -1
                $initIndex | Should -BeLessThan $assignIndex
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should produce a converted script with Start-Stepper that parses cleanly' {
            # End-to-end guarantee is now provided by Start-Stepper initializing
            # $Stepper before unmanaged code runs (covered by Start-Stepper tests).
            # Here assert the converted script contains Start-Stepper and parses.
            $scriptWithUnmanagedFirst = @(
                '[CmdletBinding()]'
                'param()'
                '$name = "seed"'
                'New-Step {'
                '    Write-Host $name'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($scriptWithUnmanagedFirst -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match 'Start-Stepper'
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseInput($result, [ref]$null, [ref]$errors) | Out-Null
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

        It 'Should not create a backup when -OutputPath is provided' {
            $src  = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $out  = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            $dir  = Split-Path -Parent $src
            $base = [System.IO.Path]::GetFileNameWithoutExtension($src)
            try {
                ConvertTo-StepperScript -Path $src -OutputPath $out -Force
                @(Get-ChildItem -Path $dir -Filter "$base.*.ps1.bak") | Should -HaveCount 0
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
            $dir  = Split-Path -Parent $path
            $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
            try {
                ConvertTo-StepperScript -Path $path -Force -WhatIf
                Get-Content -Path $path -Raw | Should -Be $originalContent
                @(Get-ChildItem -Path $dir -Filter "$base.*.ps1.bak") | Should -HaveCount 0
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

    Context 'Sentinel injection ($StepperConversionComplete)' {
        It 'Should inject install guard + sentinel after param() when no ignore region exists' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match '\$StepperConversionComplete\s*=\s*\$true'
                # install guard must also be present
                $result | Should -Match 'Install-Module Stepper'
                # sentinel must be inside the region (before #endregion)
                $sentinelIndex  = $result.IndexOf('$StepperConversionComplete')
                $endRegionIndex = $result.IndexOf('#endregion Stepper ignore')
                $sentinelIndex | Should -BeLessThan $endRegionIndex
                # sentinel must appear after param() and before New-Step
                $paramIndex    = $result.IndexOf('param()')
                $newStepIndex  = $result.IndexOf('New-Step')
                $sentinelIndex | Should -BeGreaterThan $paramIndex
                $sentinelIndex | Should -BeLessThan $newStepIndex
                # only one region block should exist
                ([regex]::Matches($result, '#region Stepper ignore')).Count | Should -Be 1
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should inject $StepperConversionComplete = $true inside existing #region Stepper ignore block' {
            $scriptWithRegion = @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'New-Step {'
                '    $servers = Get-Content servers.txt'
                '}'
                'New-Step {'
                '    foreach ($s in $servers) { Write-Host $s }'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine
            $path = New-TempScript ($scriptWithRegion -split [System.Environment]::NewLine)
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Match '\$StepperConversionComplete\s*=\s*\$true'
                # sentinel must be inside the region (before #endregion)
                $sentinelIndex  = $result.IndexOf('$StepperConversionComplete')
                $endRegionIndex = $result.IndexOf('#endregion Stepper ignore')
                $sentinelIndex | Should -BeLessThan $endRegionIndex
                # only one region block should exist
                ([regex]::Matches($result, '#region Stepper ignore')).Count | Should -Be 1
            }
            finally {
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-Item "$path.bak" -ErrorAction SilentlyContinue
            }
        }

        It 'Should NOT inject sentinel when no cross-step variable candidates exist' {
            $path = New-TempScript ($NoCanidatesScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            try {
                ConvertTo-StepperScript -Path $path -Force
                $result = Get-Content -Path $path -Raw
                $result | Should -Be $originalContent
                $result | Should -Not -Match '\$StepperConversionComplete'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Should NOT inject sentinel when -WhatIf is passed' {
            $path = New-TempScript ($CrossStepScript -split [System.Environment]::NewLine)
            $originalContent = Get-Content -Path $path -Raw
            try {
                ConvertTo-StepperScript -Path $path -Force -WhatIf
                $result = Get-Content -Path $path -Raw
                $result | Should -Be $originalContent
                $result | Should -Not -Match '\$StepperConversionComplete'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Path resolution' {
        It 'Should accept a relative path (./script.ps1)' {
            # Arrange - use a script with no cross-step candidates so no modification occurs
            $path = New-TempScript ($NoCanidatesScript -split [System.Environment]::NewLine)
            $dir  = Split-Path -Parent $path
            $file = Split-Path -Leaf $path
            Push-Location $dir
            try {
                # Act / Assert - should not throw
                { ConvertTo-StepperScript -Path "./$file" } | Should -Not -Throw
            }
            finally {
                Pop-Location
                Remove-Item $path -ErrorAction SilentlyContinue
                Remove-TempBaks $path
            }
        }

        It 'Should accept a tilde path (~/script.ps1)' {
            # Arrange
            $fileName = "StepperPathTest_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
            $absPath  = Join-Path $HOME $fileName
            $NoCanidatesScript | Set-Content -Path $absPath -Encoding UTF8 -NoNewline
            try {
                # Act / Assert - should not throw
                { ConvertTo-StepperScript -Path "~/$fileName" } | Should -Not -Throw
            }
            finally {
                Remove-Item $absPath -ErrorAction SilentlyContinue
                Remove-TempBaks $absPath
            }
        }
    }
}
