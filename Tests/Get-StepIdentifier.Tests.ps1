BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepIdentifier.ps1"
}

Describe 'Get-StepIdentifier' -Tag 'Unit' {
    Context 'When called directly from a user script' {
        It 'Returns a string in filepath:line format' {
            $result = Get-StepIdentifier
            $result | Should -Match '^.+:\d+$'
        }

        It 'Returns a positive line number' {
            $result = Get-StepIdentifier
            $linePart = [int]($result -split ':')[-1]
            $linePart | Should -BeGreaterThan 0
        }

        It 'Returns a path to an existing file' {
            $result = Get-StepIdentifier
            $filePart = $result.Substring(0, $result.LastIndexOf(':'))
            $filePart | Should -Exist
        }
    }

    Context 'When call stack has only module frames' {
        BeforeAll {
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $stepperDir = Split-Path -Path $PSScriptRoot -Parent
            $script:ModuleOnlyFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Private${sep}Get-StepIdentifier.ps1"
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Public${sep}New-Step.ps1"
                    ScriptLineNumber = 42
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $null
                    ScriptLineNumber = 0
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:ModuleOnlyFrames }
        }

        It 'Throws a terminating error' {
            { Get-StepIdentifier -ErrorAction Stop } | Should -Throw
        }

        It 'Throws with StepIdentifierNotDetermined error id' {
            try {
                Get-StepIdentifier -ErrorAction Stop
            } catch {
                $_.FullyQualifiedErrorId | Should -Match 'StepIdentifierNotDetermined'
            }
        }
    }

    Context 'When call stack includes Private/ frames before user script' {
        BeforeAll {
            $script:UserScript1 = Join-Path $TestDrive 'user-script.ps1'
            Set-Content -Path $script:UserScript1 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $stepperDir = Split-Path -Path $PSScriptRoot -Parent
            $script:PrivateFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Private${sep}Get-StepIdentifier.ps1"
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Private${sep}Some-Helper.ps1"
                    ScriptLineNumber = 10
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript1
                    ScriptLineNumber = 3
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:PrivateFrames }
        }

        It 'Skips Private/ frames and returns user script identifier' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript1}:3"
        }
    }

    Context 'When call stack includes Public/ frames before user script' {
        BeforeAll {
            $script:UserScript2 = Join-Path $TestDrive 'user-script2.ps1'
            Set-Content -Path $script:UserScript2 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $stepperDir = Split-Path -Path $PSScriptRoot -Parent
            $script:PublicFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Public${sep}New-Step.ps1"
                    ScriptLineNumber = 100
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript2
                    ScriptLineNumber = 7
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:PublicFrames }
        }

        It 'Skips Public/ frames and returns user script identifier' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript2}:7"
        }
    }

    Context 'When call stack includes Stepper.psm1 frame before user script' {
        BeforeAll {
            $script:UserScript3 = Join-Path $TestDrive 'user-script3.ps1'
            Set-Content -Path $script:UserScript3 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $stepperDir = Split-Path -Path $PSScriptRoot -Parent
            $script:Psm1Frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Stepper.psm1"
                    ScriptLineNumber = 20
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript3
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:Psm1Frames }
        }

        It 'Skips Stepper.psm1 frame and returns user script identifier' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript3}:5"
        }
    }

    Context 'When call stack has multiple module frames followed by user script' {
        BeforeAll {
            $script:UserScript4 = Join-Path $TestDrive 'user-script4.ps1'
            Set-Content -Path $script:UserScript4 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $stepperDir = Split-Path -Path $PSScriptRoot -Parent
            $script:MixedFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Private${sep}Get-StepIdentifier.ps1"
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Public${sep}New-Step.ps1"
                    ScriptLineNumber = 42
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${stepperDir}${sep}Stepper.psm1"
                    ScriptLineNumber = 8
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript4
                    ScriptLineNumber = 12
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:MixedFrames }
        }

        It 'Returns the first non-module user script frame' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript4}:12"
        }
    }

    Context 'When Stepper.psm1 frame comes from a built artefact (not the source repo)' {
        # Regression: Get-StepIdentifier used to skip module frames only by comparing
        # against the source repo path, so a built artefact's Stepper.psm1 frame was
        # mistaken for the user's script and New-Step validated/repaired the module.
        BeforeAll {
            $script:UserScript5 = Join-Path $TestDrive 'user-script5.ps1'
            Set-Content -Path $script:UserScript5 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $script:ArtefactFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${TestDrive}${sep}Artefacts${sep}Unpacked${sep}Stepper${sep}Stepper.psm1"
                    ScriptLineNumber = 8
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript5
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:ArtefactFrames }
        }

        It 'Skips the built artefact Stepper.psm1 frame and returns the user script' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript5}:5"
        }
    }

    Context 'When module frames come from an installed module path' {
        BeforeAll {
            $script:UserScript6 = Join-Path $TestDrive 'user-script6.ps1'
            Set-Content -Path $script:UserScript6 -Value 'New-Step { }'
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $script:InstalledFrames = @(
                [PSCustomObject]@{
                    ScriptName       = "${TestDrive}${sep}Modules${sep}Stepper${sep}Stepper.psm1"
                    ScriptLineNumber = 700
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $script:UserScript6
                    ScriptLineNumber = 2
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack { $script:InstalledFrames }
        }

        It 'Skips the installed Stepper.psm1 frame and returns the user script' {
            $result = Get-StepIdentifier
            $result | Should -Be "${script:UserScript6}:2"
        }
    }
}
