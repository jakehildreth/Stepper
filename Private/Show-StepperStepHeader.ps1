function Show-StepperStepHeader {
    <#
    .SYNOPSIS
        Displays a header for the current Stepper step.
    
    .DESCRIPTION
        Shows a formatted header indicating the current step number,
        total steps, and step name.
    
    .PARAMETER StepName
        The name of the current step.
    
    .PARAMETER StepNumber
        The current step number (1-based).
    
    .PARAMETER TotalSteps
        The total number of steps in the Stepper.
    
    .EXAMPLE
        Show-StepperStepHeader -StepName "Environment Check" -StepNumber 1 -TotalSteps 5
        
        Displays header for step 1 of 5.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,
        
        [Parameter(Mandatory = $true)]
        [int]$StepNumber,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalSteps
    )
    
    $border = "-" * 70
    Write-Host "`n$border" -ForegroundColor Cyan
    Write-Host "Step $StepNumber of ${TotalSteps}: $StepName" -ForegroundColor Cyan
    Write-Host "$border" -ForegroundColor Cyan
}
