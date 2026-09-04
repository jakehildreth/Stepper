BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Read-StepperChoice.ps1"
}

Describe 'Read-StepperChoice' -Tag 'Unit' {
    Context 'Test hook' {
        It 'Dequeues a queued response instead of prompting' {
            $script:__StepperTestResponses = [System.Collections.Generic.Queue[string]]::new()
            $script:__StepperTestResponses.Enqueue('r')

            $result = Read-StepperChoice -NonInteractiveDefault 's'

            $result | Should -Be 'r'
            $script:__StepperTestResponses.Count | Should -Be 0
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Drains the queue in FIFO order across calls' {
            $script:__StepperTestResponses = [System.Collections.Generic.Queue[string]]::new()
            'm', 'r' | ForEach-Object { $script:__StepperTestResponses.Enqueue($_) }

            $first = Read-StepperChoice
            $second = Read-StepperChoice

            $first | Should -Be 'm'
            $second | Should -Be 'r'
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
        }
    }

    Context 'No hook' {
        It 'Falls back to Read-Host when no queue is set' {
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
            Mock Read-Host { 'x' }

            Read-StepperChoice | Should -Be 'x'
        }

        It 'Returns the non-interactive default when Read-Host throws' {
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
            Mock Read-Host { throw 'non-interactive' }

            Read-StepperChoice -NonInteractiveDefault 's' | Should -Be 's'
        }
    }
}
