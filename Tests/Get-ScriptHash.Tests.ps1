BeforeAll {
    # Dot-source the private function directly for testing
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
}

Describe 'Get-ScriptHash' {
    BeforeEach {
        # Create a temporary test directory
        $TestDrive = [System.IO.Path]::GetTempPath()
        $TestFile = Join-Path $TestDrive "test-$(New-Guid).ps1"
    }

    AfterEach {
        # Clean up test files
        if (Test-Path $TestFile) {
            Remove-Item $TestFile -Force
        }
    }

    Context 'When calculating hash for script files' {
        It 'Should return a 64-character hex string' {
            'Write-Host "Test"' | Out-File -FilePath $TestFile -Encoding UTF8

            $hash = Get-ScriptHash -ScriptPath $TestFile

            $hash | Should -BeOfType [string]
            $hash.Length | Should -Be 64
            $hash | Should -Match '^[0-9A-F]+$'
        }

        It 'Should return consistent hash for same content' {
            $content = 'Write-Host "Hello World"'
            $content | Out-File -FilePath $TestFile -Encoding UTF8

            $hash1 = Get-ScriptHash -ScriptPath $TestFile
            $hash2 = Get-ScriptHash -ScriptPath $TestFile

            $hash1 | Should -Be $hash2
        }

        It 'Should return different hash for different content' {
            'Write-Host "Test 1"' | Out-File -FilePath $TestFile -Encoding UTF8
            $hash1 = Get-ScriptHash -ScriptPath $TestFile

            'Write-Host "Test 2"' | Out-File -FilePath $TestFile -Encoding UTF8
            $hash2 = Get-ScriptHash -ScriptPath $TestFile

            $hash1 | Should -Not -Be $hash2
        }

        It 'Should detect whitespace changes' {
            'Write-Host "Test"' | Out-File -FilePath $TestFile -Encoding UTF8
            $hash1 = Get-ScriptHash -ScriptPath $TestFile

            'Write-Host  "Test"' | Out-File -FilePath $TestFile -Encoding UTF8
            $hash2 = Get-ScriptHash -ScriptPath $TestFile

            $hash1 | Should -Not -Be $hash2
        }

        It 'Should detect line ending changes' {
            "Line1`nLine2" | Out-File -FilePath $TestFile -Encoding UTF8 -NoNewline
            $hash1 = Get-ScriptHash -ScriptPath $TestFile

            "Line1`r`nLine2" | Out-File -FilePath $TestFile -Encoding UTF8 -NoNewline
            $hash2 = Get-ScriptHash -ScriptPath $TestFile

            $hash1 | Should -Not -Be $hash2
        }

        It 'Should handle empty files' {
            ' ' | Out-File -FilePath $TestFile -Encoding UTF8 -NoNewline

            $hash = Get-ScriptHash -ScriptPath $TestFile

            $hash | Should -Not -BeNullOrEmpty
            $hash.Length | Should -Be 64
        }

        It 'Should handle multi-line scripts' {
            $script = @'
function Test-Function {
    param($Name)
    Write-Host "Hello $Name"
}

Test-Function -Name "World"
'@
            $script | Out-File -FilePath $TestFile -Encoding UTF8

            $hash = Get-ScriptHash -ScriptPath $TestFile

            $hash | Should -Not -BeNullOrEmpty
            $hash.Length | Should -Be 64
        }
    }

    Context 'Error handling' {
        It 'Should throw when file does not exist' {
            $nonExistentFile = Join-Path $TestDrive "does-not-exist.ps1"

            { Get-ScriptHash -ScriptPath $nonExistentFile } | Should -Throw
        }

        It 'Should require ScriptPath parameter' {
            { Get-ScriptHash } | Should -Throw
        }
    }
}
