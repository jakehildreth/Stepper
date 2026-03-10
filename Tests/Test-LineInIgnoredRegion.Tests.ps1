BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Test-LineInIgnoredRegion.ps1"
}

Describe 'Test-LineInIgnoredRegion' -Tag 'Unit' {
    Context 'When IgnoredRegions is empty' {
        It 'Should return $false' {
            $result = Test-LineInIgnoredRegion -LineIndex 5 -IgnoredRegions @()
            $result | Should -BeFalse
        }
    }

    Context 'When checking a single region (Start = 5, End = 10)' {
        BeforeAll {
            $region = @(@{ Start = 5; End = 10 })
        }

        It 'Should return $true when LineIndex falls within Start..End range' {
            $result = Test-LineInIgnoredRegion -LineIndex 7 -IgnoredRegions $region
            $result | Should -BeTrue
        }

        It 'Should return $true at exact Start boundary' {
            $result = Test-LineInIgnoredRegion -LineIndex 5 -IgnoredRegions $region
            $result | Should -BeTrue
        }

        It 'Should return $true at exact End boundary' {
            $result = Test-LineInIgnoredRegion -LineIndex 10 -IgnoredRegions $region
            $result | Should -BeTrue
        }

        It 'Should return $false one index below Start' {
            $result = Test-LineInIgnoredRegion -LineIndex 4 -IgnoredRegions $region
            $result | Should -BeFalse
        }

        It 'Should return $false one index above End' {
            $result = Test-LineInIgnoredRegion -LineIndex 11 -IgnoredRegions $region
            $result | Should -BeFalse
        }
    }

    Context 'When checking multiple regions (2..4, 8..12)' {
        BeforeAll {
            $regions = @(
                @{ Start = 2; End = 4 },
                @{ Start = 8; End = 12 }
            )
        }

        It 'Should return $true when line falls in the second region' {
            $result = Test-LineInIgnoredRegion -LineIndex 10 -IgnoredRegions $regions
            $result | Should -BeTrue
        }

        It 'Should return $false in the gap between the two regions' {
            $result = Test-LineInIgnoredRegion -LineIndex 6 -IgnoredRegions $regions
            $result | Should -BeFalse
        }
    }
}
