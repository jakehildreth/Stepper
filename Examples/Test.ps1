Write-Output 'This code is useless. Delete it!' | Out-Null

New-Step {
    $Stepper.Name = Read-Host 'Enter your name'
}

Write-Output 'This code should execute every time the script runs.' | Out-Null
Write-Output 'Mark this block w/ a special comment so Stepper ignores it.' |
    Out-Null
$Stepper.ProcessCount = (Get-Process).Count
$Stepper.ItemCount = (Get-ChildItem).Count
$Stepper.CollectionTime = Get-Date

New-Step {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host ""
        Write-Host "Oh no! A crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Processes currently running: $($Stepper.ItemCount)"
}

Write-Output "Make this code resumable. Wrap it in New-Step {}." | Out-Null
Write-Host "Hey, $($Stepper.Name)!"
Write-Host "There are $($Stepper.ItemCount) items in this directory."
