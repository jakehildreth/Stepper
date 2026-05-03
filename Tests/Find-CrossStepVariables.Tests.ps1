BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Find-CrossStepVariables.ps1"
}

Describe 'Find-CrossStepVariables' -Tag 'Unit' {
    Context 'When script has no New-Step blocks' {
        It 'Should return an empty array' {
            $content = @(
                '[CmdletBinding()]'
                'param()'
                'Write-Host "no steps"'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -HaveCount 0
        }
    }

    Context 'When script has a single New-Step block' {
        It 'Should return an empty array (no cross-step candidates possible)' {
            $content = @(
                'New-Step {'
                '    $servers = Get-Content servers.txt'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -HaveCount 0
        }
    }

    Context 'When a variable is written in step 1 and read in step 2' {
        It 'Should return the variable name' {
            $content = @(
                'New-Step {'
                '    $servers = Get-Content servers.txt'
                '}'
                'New-Step {'
                '    foreach ($s in $servers) { Write-Host $s }'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Contain 'servers'
        }
    }

    Context 'When a variable is only used within one step' {
        It 'Should not be returned' {
            $content = @(
                'New-Step {'
                '    $temp = Get-Process'
                '    Write-Host $temp.Count'
                '}'
                'New-Step {'
                '    Write-Host "done"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'temp'
        }
    }

    Context 'When a variable is written in step 2 and read in step 1 (backward reference)' {
        It 'Should not be returned (only forward cross-step refs are candidates)' {
            $content = @(
                'New-Step {'
                '    Write-Host $results'
                '}'
                'New-Step {'
                '    $results = Invoke-Something'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'results'
        }
    }

    Context 'When a variable already uses $Stepper. notation' {
        It 'Should not be returned' {
            $content = @(
                'New-Step {'
                '    $Stepper.Servers = Get-Content servers.txt'
                '}'
                'New-Step {'
                '    foreach ($s in $Stepper.Servers) { Write-Host $s }'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'Servers'
            $result | Should -Not -Contain 'Stepper'
        }
    }

    Context 'When PowerShell automatic variables are assigned inside a step' {
        It 'Should not return $_ (PSItem)' {
            $content = @(
                'New-Step {'
                '    $_ = "something"'
                '}'
                'New-Step {'
                '    Write-Host $_'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain '_'
        }

        It 'Should not return $ErrorActionPreference' {
            $content = @(
                'New-Step {'
                '    $ErrorActionPreference = "Stop"'
                '}'
                'New-Step {'
                '    Write-Host $ErrorActionPreference'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'ErrorActionPreference'
        }

        It 'Should not return $PSScriptRoot' {
            $content = @(
                'New-Step {'
                '    $path = Join-Path $PSScriptRoot "data.txt"'
                '}'
                'New-Step {'
                '    $path2 = Join-Path $PSScriptRoot "out.txt"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'PSScriptRoot'
        }
    }

    Context 'When multiple variables cross step boundaries' {
        It 'Should return all qualifying variable names' {
            $content = @(
                'New-Step {'
                '    $servers = Get-Content servers.txt'
                '    $startTime = Get-Date'
                '    $localOnly = 42'
                '}'
                'New-Step {'
                '    foreach ($s in $servers) { Write-Host $s }'
                '    $elapsed = (Get-Date) - $startTime'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Contain 'servers'
            $result | Should -Contain 'startTime'
            $result | Should -Not -Contain 'localOnly'
        }
    }

    Context 'When the same variable is read in multiple later steps' {
        It 'Should return the variable name only once' {
            $content = @(
                'New-Step {'
                '    $data = Get-Content data.txt'
                '}'
                'New-Step {'
                '    Write-Host $data.Count'
                '}'
                'New-Step {'
                '    $data | ForEach-Object { Write-Host $_ }'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            ($result | Where-Object { $_ -eq 'data' }) | Should -HaveCount 1
        }
    }

    Context 'When called with -ScriptPath parameter' {
        It 'Should accept a file path and return results' {
            $scriptPath = Join-Path $TestDrive "cross-step-test-$(New-Guid).ps1"
            @(
                'New-Step {'
                '    $items = Get-ChildItem'
                '}'
                'New-Step {'
                '    Write-Host $items.Count'
                '}'
                'Stop-Stepper'
            ) | Set-Content -Path $scriptPath

            $result = Find-CrossStepVariables -ScriptPath $scriptPath
            $result | Should -Contain 'items'
        }
    }

    Context 'When a variable is assigned in unmanaged (script-level) code and read in a step' {
        It 'Should return the variable name' {
            $content = @(
                '$servers = Get-Content servers.txt'
                'New-Step {'
                '    foreach ($s in $servers) { Write-Host $s }'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Contain 'servers'
        }

        It 'Should return the variable name even when there is only one New-Step block' {
            $content = @(
                '$config = Import-PowerShellDataFile config.psd1'
                'New-Step {'
                '    Apply-Config $config'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Contain 'config'
        }

        It 'Should NOT return a variable assigned in unmanaged code that is never read in any step' {
            $content = @(
                '$unused = "hello"'
                'New-Step {'
                '    Write-Host "step 1"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'unused'
        }

        It 'Should NOT return automatic variables assigned in unmanaged code' {
            $content = @(
                '$ErrorActionPreference = "Stop"'
                'New-Step {'
                '    Write-Host $ErrorActionPreference'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'ErrorActionPreference'
        }
    }

    Context 'When a variable is written and read inside a -Retry step' {
        It 'Should return the variable name (it must survive across retries)' {
            $content = @(
                'New-Step -Retry -MaxRetries 3 {'
                '    if ($null -eq $attempt) { $attempt = 0 }'
                '    $attempt++'
                '    if ($attempt -lt 3) { throw "retry" }'
                '    Write-Host "done on $attempt"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Contain 'attempt'
        }

        It 'Should NOT return a variable that is only written (never read) inside a -Retry step' {
            $content = @(
                'New-Step -Retry -MaxRetries 3 {'
                '    $writeOnly = Get-Date'
                '    throw "retry"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'writeOnly'
        }

        It 'Should NOT return automatic variables inside a -Retry step' {
            $content = @(
                'New-Step -Retry -MaxRetries 3 {'
                '    if ($null -eq $ErrorActionPreference) { $ErrorActionPreference = "Stop" }'
                '    throw "retry"'
                '}'
                'Stop-Stepper'
            ) -join [System.Environment]::NewLine

            $result = Find-CrossStepVariables -ScriptContent $content
            $result | Should -Not -Contain 'ErrorActionPreference'
        }
    }
}
