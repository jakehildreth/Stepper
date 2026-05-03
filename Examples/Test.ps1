Write-Output 'This code is useless. Delete it!' | Out-Null

New-Step 'Get user''s name' {
    $Name = Read-Host 'Enter your name'
}

Write-Output 'This code should execute every time the script runs.' | Out-Null
Write-Output 'Mark this block w/ a special comment so Stepper ignores it.' |
    Out-Null
$ProcessCount = (Get-Process).Count
$ItemCount = (Get-ChildItem).Count
$CollectionTime = Get-Date

New-Step -NoLog {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host ""
        Write-Host "Oh no! A crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Hey, $($Name)!"
    Write-Host "There are $($ProcessCount) processes currently running."
}

Write-Output "Make this code resumable. Wrap it in New-Step {}." | Out-Null
Write-Host "There are $($ItemCount) items in this directory."

New-Step 'Retry example with exponential backoff' -Retry -RetryInterval 2 -MaxRetries 3 {
    Write-Host "Attempting operation..."
    # Simulate a transient failure (fails first 2 times, succeeds on 3rd)
    if ($null -eq $RetryAttempt) {
        $RetryAttempt = 0
    }
    $RetryAttempt++
    
    if ($RetryAttempt -lt 3) {
        throw "Transient error (attempt $($RetryAttempt)). Will retry..."
    }
    Write-Host "Success on attempt $($RetryAttempt)!"
}
