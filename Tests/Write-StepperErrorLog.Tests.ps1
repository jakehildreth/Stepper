BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Write-StepperErrorLog.ps1"
}

Describe 'Write-StepperErrorLog' -Tag 'Unit' {
    BeforeAll {
        Mock Write-Warning {}
        $global:Error.Clear()
        Write-Error 'detail-message-abc' -ErrorAction SilentlyContinue
        Get-Item -Path (Join-Path $TestDrive 'missing-file') -ErrorAction SilentlyContinue
        $script:Records = @($global:Error[0..1])
        $global:Error.Clear()
    }

    BeforeEach {
        $script:ErrorLog = Join-Path $TestDrive "errors-$(New-Guid).log"
    }

    It 'Writes the step label as a header' {
        Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $script:ErrorLog -StepLabel "Step 2/5 - 'Deploy'"
        Get-Content -Path $script:ErrorLog -Raw | Should -Match "Step 2/5 - 'Deploy'"
    }

    It 'Writes the message of every record' {
        Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $script:ErrorLog -StepLabel 'Step 1/1'
        $content = Get-Content -Path $script:ErrorLog -Raw
        $content | Should -Match 'detail-message-abc'
        $content | Should -Match 'missing-file'
    }

    It 'Writes the fully qualified error id and category' {
        Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $script:ErrorLog -StepLabel 'Step 1/1'
        $content = Get-Content -Path $script:ErrorLog -Raw
        $content | Should -Match 'PathNotFound'
        $content | Should -Match 'ObjectNotFound'
    }

    It 'Appends to an existing error log' {
        Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $script:ErrorLog -StepLabel 'Step 1/2'
        Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $script:ErrorLog -StepLabel 'Step 2/2'
        $content = Get-Content -Path $script:ErrorLog -Raw
        $content | Should -Match 'Step 1/2'
        $content | Should -Match 'Step 2/2'
    }

    It 'Warns and does not throw when the log cannot be written' {
        $badPath = Join-Path (Join-Path $TestDrive 'no-such-dir') 'errors.log'
        { Write-StepperErrorLog -ErrorRecord $script:Records -LogPath $badPath -StepLabel 'Step 1/1' } | Should -Not -Throw
        Should -Invoke Write-Warning -ParameterFilter { $Message -match 'could not write' }
    }
}
