function Show-StepperHeader {
    <#
    .SYNOPSIS
        Displays a formatted header for the Stepper.
    
    .DESCRIPTION
        Shows a visually formatted header with the Stepper tool name
        and version at the start of the Stepper.
    
    .PARAMETER Title
        The title to display in the header. Default is "Multi-Step Stepper Tool".
    
    .PARAMETER Version
        The version string to display. Default is "1.0.0".
    
    .EXAMPLE
        Show-StepperHeader
        
        Displays the default header.
    
    .EXAMPLE
        Show-StepperHeader -Title "Security Stepper" -Version "2.0.0"
        
        Displays a custom header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = "Multi-Step Stepper Tool",
        
        [Parameter(Mandatory = $false)]
        [string]$Version = "1.0.0"
    )
    
    $border = "=" * 70
    Write-Host $border -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host " Version $Version" -ForegroundColor Cyan
    Write-Host $border -ForegroundColor Cyan
    Write-Host ""
}
