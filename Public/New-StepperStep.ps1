function New-StepperStep {
    <#
    .SYNOPSIS
        Creates a new step script file from a template.
    
    .DESCRIPTION
        Generates a new step script file with proper comment-based help
        and basic structure. The file is ready to be customized with your
        specific step logic.
    
    .PARAMETER Name
        Name of the step (e.g., "DiskSpace").
        The "Step-" prefix will be added automatically if not present.
    
    .PARAMETER Path
        Directory where the step file will be created.
        Defaults to "Steps" subdirectory in current location.
    
    .PARAMETER AcceptsAllResults
        If specified, adds the $AllResults parameter to the step script.
    
    .PARAMETER Force
        Overwrite existing file if it exists.
    
    .EXAMPLE
        New-StepperStep -Name "DiskSpace"
        
        Creates Steps/Step-DiskSpace.ps1 with basic template.
    
    .EXAMPLE
        New-StepperStep -Name "GenerateReport" -AcceptsAllResults
        
        Creates a step that accepts results from previous steps.
    
    .EXAMPLE
        New-StepperStep -Name "CustomCheck" -Path "C:\MySteps"
        
        Creates step file in custom directory.
    
    .OUTPUTS
        System.IO.FileInfo - The created step file.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$AcceptsAllResults,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting New-StepperStep for '$Name'"
        
        # Ensure name has Step- prefix
        if ($Name -notlike 'Step-*') {
            $Name = "Step-$Name"
        }
        
        # Default path to Steps subdirectory
        if (-not $Path) {
            $Path = Join-Path -Path (Get-Location).Path -ChildPath "Steps"
        }
        
        # Create directory if it doesn't exist
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $Path"
        }
        
        $stepPath = Join-Path -Path $Path -ChildPath "$Name.ps1"
    }
    
    process {
        try {
            # Check if file exists
            if ((Test-Path $stepPath) -and -not $Force) {
                throw "Step file already exists: $stepPath. Use -Force to overwrite."
            }
            
            if ($PSCmdlet.ShouldProcess($stepPath, "Create step file")) {
                # Build step content based on parameters
                $paramBlock = if ($AcceptsAllResults) {
                    @"
param(
    [Parameter(Mandatory = `$false)]
    [hashtable]`$AllResults
)

"@
                } else {
                    @"
param()

"@
                }
                
                $allResultsExample = if ($AcceptsAllResults) {
                    @"

    # Access results from previous steps
    # `$previousStep = `$AllResults['PreviousStepName']
    # `$data = `$previousStep.SomeProperty
"@
                } else {
                    ""
                }
                
                $stepContent = @"
# $Name
<#
.SYNOPSIS
    Brief description of what this step does.

.DESCRIPTION
    Detailed description of the step's purpose and what it checks or performs.
$(if ($AcceptsAllResults) {
"
.PARAMETER AllResults
    Hashtable containing results from all previously completed steps.
"})

.OUTPUTS
    Returns a hashtable with the step's results.
    These results can be accessed by subsequent steps if they have acceptsAllResults: true.

.NOTES
    This step is part of a Stepper workflow.
    It will be executed in the order specified in the JSON configuration.
#>

$paramBlock
Write-Host "`n--- $($Name.Replace('Step-', '')) ---" -ForegroundColor Yellow

try {$allResultsExample
    # Your step logic here
    Write-Host "  Running $($Name.Replace('Step-', ''))..." -ForegroundColor Gray
    
    # Example: Perform your checks, gather data, etc.
    `$result = @{
        Status = "Success"
        Details = "Step completed successfully"
        # Add your custom properties here
    }
    
    Write-Host "  ✓ Step completed" -ForegroundColor Green
    
    # Return results for potential use by other steps
    return `$result
} catch {
    Write-Error "Failed to execute $Name`: `$_"
    return `$false
}
"@
                
                $stepContent | Set-Content -Path $stepPath -Encoding UTF8 -Force
                Write-Host "Created step: $stepPath" -ForegroundColor Green
                
                # Return the step file
                Get-Item $stepPath
            }
        } catch {
            Write-Error "Failed to create step file: $_"
            throw
        }
    }
    
    end {
        Write-Verbose "Completed New-StepperStep"
    }
}
