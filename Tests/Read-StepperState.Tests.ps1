BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Write-StepperState.ps1"
    . "$ModulePath/Private/Read-StepperState.ps1"
}

Describe 'Read-StepperState' -Tag 'Unit' {
    Context 'When state file does not exist' {
        It 'Should return $null' {
            $result = Read-StepperState -StatePath (Join-Path $TestDrive 'nonexistent.stepper')
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When state file exists and is valid' {
        BeforeAll {
            $script:ValidStatePath = Join-Path $TestDrive 'valid.stepper'
            $writeParams = @{
                StatePath         = $script:ValidStatePath
                ScriptHash        = 'aabbccdd'
                LastCompletedStep = '/tmp/script.ps1:15'
                StepName          = 'Setup environment'
                StepNumber        = 2
                StepperData       = @{ Key1 = 'value1'; Num1 = 99 }
                ScriptContents    = 'Write-Host "hello"'
            }
            Write-StepperState @writeParams
            $script:State = Read-StepperState -StatePath $script:ValidStatePath
        }

        It 'Should return a non-null object on round-trip' {
            $script:State | Should -Not -BeNullOrEmpty
        }

        It 'Should return an object with all expected properties' {
            $props = $script:State.PSObject.Properties.Name
            $props | Should -Contain 'ScriptHash'
            $props | Should -Contain 'LastCompletedStep'
            $props | Should -Contain 'LastCompletedStepName'
            $props | Should -Contain 'LastCompletedStepNumber'
            $props | Should -Contain 'Timestamp'
            $props | Should -Contain 'StepperData'
            $props | Should -Contain 'ScriptContents'
        }

        It 'Should return the correct ScriptHash' {
            $script:State.ScriptHash | Should -Be 'aabbccdd'
        }

        It 'Should return the correct LastCompletedStep' {
            $script:State.LastCompletedStep | Should -Be '/tmp/script.ps1:15'
        }

        It 'Should return the correct LastCompletedStepName' {
            $script:State.LastCompletedStepName | Should -Be 'Setup environment'
        }

        It 'Should return the correct LastCompletedStepNumber' {
            $script:State.LastCompletedStepNumber | Should -Be 2
        }

        It 'Should return the correct ScriptContents' {
            $script:State.ScriptContents | Should -Be 'Write-Host "hello"'
        }

        It 'Should correctly deserialize StepperData hashtable values' {
            $script:State.StepperData['Key1'] | Should -Be 'value1'
            $script:State.StepperData['Num1'] | Should -Be 99
        }
    }

    Context 'When state file contains corrupt XML' {
        BeforeAll {
            $script:CorruptPath = Join-Path $TestDrive 'corrupt.stepper'
            Set-Content -Path $script:CorruptPath -Value '<<< NOT VALID XML >>>'
        }

        It 'Should return $null' {
            $result = Read-StepperState -StatePath $script:CorruptPath -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Should write a non-terminating error with StateReadFailed error id' {
            $errors = @()
            Read-StepperState -StatePath $script:CorruptPath -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StateReadFailed*' } | Should -Not -BeNullOrEmpty
        }
    }
}
