Write-Output 'This code is useless. Delete it!' | Out-Null

New-Step 'Get user''s name' {
    $Stepper.Name = Read-Host 'Enter your name'
}

Write-Output 'This code should execute every time the script runs.' | Out-Null
Write-Output 'Mark this block w/ a special comment so Stepper ignores it.' |
    Out-Null
$Stepper.ProcessCount = (Get-Process).Count
$Stepper.ItemCount = (Get-ChildItem).Count
$Stepper.CollectionTime = Get-Date

New-Step -NoLog {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host ""
        Write-Host "Oh no! A crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Hey, $($Stepper.Name)!"
    Write-Host "There are $($Stepper.ProcessCount) processes currently running."
}

Write-Output "Make this code resumable. Wrap it in New-Step {}." | Out-Null
Write-Host "There are $($Stepper.ItemCount) items in this directory."

New-Step 'Retry example with exponential backoff' -Retry -RetryInterval 2 -MaxRetries 3 {
    Write-Host "Attempting operation..."
    # Simulate a transient failure (fails first 2 times, succeeds on 3rd)
    if ($null -eq $Stepper.RetryAttempt) {
        $Stepper.RetryAttempt = 0
    }
    $Stepper.RetryAttempt++
    
    if ($Stepper.RetryAttempt -lt 3) {
        throw "Transient error (attempt $($Stepper.RetryAttempt)). Will retry..."
    }
    Write-Host "Success on attempt $($Stepper.RetryAttempt)!"
}
