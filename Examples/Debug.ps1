Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

# Temporarily add debug output to see call stack
$debugStep = {
    $cs = Get-PSCallStack
    Write-Host "Call Stack:" -ForegroundColor Yellow
    $cs | ForEach-Object {
        Write-Host "  Script: $($_.ScriptName)" -ForegroundColor Gray
        Write-Host "  Command: $($_.Command)" -ForegroundColor Gray
        Write-Host "  Line: $($_.ScriptLineNumber)" -ForegroundColor Gray
        Write-Host "" -ForegroundColor Gray
    }
}

New-Step $debugStep
