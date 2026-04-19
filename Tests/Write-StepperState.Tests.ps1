BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Write-StepperState.ps1"
}

Describe 'Write-StepperState' -Tag 'Unit' {
    Context 'When writing valid state to disk' {
        BeforeEach {
            $StatePath = Join-Path $TestDrive "state-$(New-Guid).stepper"
        }

        It 'Should create a file at the specified path' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc123' -LastCompletedStep '/tmp/test.ps1:10'
            $StatePath | Should -Exist
        }

        It 'Should write the correct ScriptHash' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'deadbeef01234567' -LastCompletedStep '/tmp/test.ps1:10'
            $state = Import-Clixml -Path $StatePath
            $state.ScriptHash | Should -Be 'deadbeef01234567'
        }

        It 'Should write the correct LastCompletedStep identifier' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:42'
            $state = Import-Clixml -Path $StatePath
            $state.LastCompletedStep | Should -Be '/tmp/test.ps1:42'
        }

        It 'Should write the correct LastCompletedStepName' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -StepName 'Install packages'
            $state = Import-Clixml -Path $StatePath
            $state.LastCompletedStepName | Should -Be 'Install packages'
        }

        It 'Should write the correct LastCompletedStepNumber' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -StepNumber 3
            $state = Import-Clixml -Path $StatePath
            $state.LastCompletedStepNumber | Should -Be 3
        }

        It 'Should preserve StepperData hashtable with mixed types' {
            $data = @{
                StringVal = 'hello'
                IntVal    = 42
                DateVal   = [datetime]::Parse('2026-01-15T10:30:00')
            }
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -StepperData $data
            $state = Import-Clixml -Path $StatePath
            $state.StepperData['StringVal'] | Should -Be 'hello'
            $state.StepperData['IntVal'] | Should -Be 42
            $state.StepperData['DateVal'] | Should -BeOfType [datetime]
        }

        It 'Should include an ISO 8601 Timestamp' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10'
            $state = Import-Clixml -Path $StatePath
            $state.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }

        It 'Should include ScriptContents when provided' {
            $contents = 'Write-Host "hello"'
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -ScriptContents $contents
            $state = Import-Clixml -Path $StatePath
            $state.ScriptContents | Should -Be $contents
        }

        It 'Should persist LogPath when provided' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -LogPath 'C:\logs\run.log'
            $state = Import-Clixml -Path $StatePath
            $state.LogPath | Should -Be 'C:\logs\run.log'
        }

        It 'Should persist LogPath as null when not provided' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10'
            $state = Import-Clixml -Path $StatePath
            $state.LogPath | Should -BeNullOrEmpty
        }

        It 'Should persist LoggingEnabled = $true when provided' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -LoggingEnabled $true
            $state = Import-Clixml -Path $StatePath
            $state.LoggingEnabled | Should -BeTrue
        }

        It 'Should persist LoggingEnabled = $false when provided' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -LoggingEnabled $false
            $state = Import-Clixml -Path $StatePath
            $state.LoggingEnabled | Should -BeFalse
        }

        It 'Should persist NoLogStepIds array when provided' {
            $ids = @('/tmp/test.ps1:5', '/tmp/test.ps1:12')
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10' -NoLogStepIds $ids
            $state = Import-Clixml -Path $StatePath
            $state.NoLogStepIds | Should -Contain '/tmp/test.ps1:5'
            $state.NoLogStepIds | Should -Contain '/tmp/test.ps1:12'
        }

        It 'Should persist NoLogStepIds as null when not provided' {
            Write-StepperState -StatePath $StatePath -ScriptHash 'abc' -LastCompletedStep '/tmp/test.ps1:10'
            $state = Import-Clixml -Path $StatePath
            $state.NoLogStepIds | Should -BeNullOrEmpty
        }
    }

    Context 'When Export-Clixml fails' {
        BeforeAll {
            Mock Export-Clixml { throw [System.IO.IOException]::new('simulated disk error') }
        }

        It 'Should write a non-terminating error with StateWriteFailed error id' {
            $errors = @()
            $failPath = Join-Path $TestDrive 'fail.stepper'
            Write-StepperState -StatePath $failPath -ScriptHash 'abc' -LastCompletedStep 'x:1' -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StateWriteFailed*' } | Should -Not -BeNullOrEmpty
        }
    }
}
