#requires -Modules Stepper
[CmdletBinding()]
param()


New-Step 'Enter Your Name' {
    $Stepper.Name = Read-Host 'Enter your name'
    Write-Verbose "Running '$($Stepper.StepName)' (step $($Stepper.StepNumber))"
}

#region Stepper ignore
Write-Output 'This code should execute every time the script runs.' | Out-Null
Write-Output 'Mark this block w/ a special comment so Stepper ignores it.' |
    Out-Null
$Stepper.ProcessCount = (Get-Process).Count
$Stepper.ItemCount = (Get-ChildItem).Count
$Stepper.CollectionTime = Get-Date
#endregion Stepper ignore

New-Step 'Display Results' {
    $response = Read-Host 'Do you want to simulate a crash? [Y/n]'
    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
        Write-Host ""
        Write-Host "Oh no! A crash..." -ForegroundColor Red
        exit
    }
    Write-Host "Hey, $($Stepper.Name)! (running '$($Stepper.StepName)')"
    Write-Host "There are $($Stepper.ProcessCount) processes currently running."
}

New-Step {
    Write-Output "Make this code resumable. Wrap it in New-Step {}." | Out-Null
    Write-Host "There are $($Stepper.ItemCount) items in this directory."
}

#

Stop-Stepper
