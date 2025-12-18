Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

Write-Host "Starting multi-step process..." -ForegroundColor Cyan
Write-Host ""

New-Step {
    Write-Host "Step 1: Downloading files..." -ForegroundColor Green
    Start-Sleep -Seconds 2
    Write-Host "  Download complete!" -ForegroundColor Gray
}

New-Step {
    Write-Host "Step 2: Processing data..." -ForegroundColor Green
    Start-Sleep -Seconds 2
    Write-Host "  Processing complete!" -ForegroundColor Gray
}

New-Step {
    Write-Host "Step 3: Uploading results..." -ForegroundColor Green
    Start-Sleep -Seconds 2
    Write-Host "  Upload complete!" -ForegroundColor Gray
}

New-Step {
    Write-Host "Step 4: Cleaning up..." -ForegroundColor Green
    Start-Sleep -Seconds 1
    Write-Host "  Cleanup complete!" -ForegroundColor Gray
}

Write-Host ""
Write-Host "All steps completed successfully!" -ForegroundColor Cyan

Stop-Stepper
