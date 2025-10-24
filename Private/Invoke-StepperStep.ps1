function Invoke-StepperStep {
    <#
    .SYNOPSIS
        Executes a single Stepper step and tracks the result.
    
    .DESCRIPTION
        Runs the script block for a given Stepper step, tracks timing,
        handles errors, and records results in the state object.
    
    .PARAMETER Step
        A PSCustomObject containing the step definition with Name, Description,
        ScriptBlock, and AcceptsAllResults properties.
    
    .PARAMETER State
        The Stepper state hashtable to update with results.
    
    .PARAMETER AllResults
        Optional hashtable containing results from all previously completed
        steps. Passed to steps that need access to prior results.
    
    .OUTPUTS
        System.Boolean - $true if step succeeded, $false if it failed.
    
    .EXAMPLE
        $success = Invoke-StepperStep -Step $stepDef -State $state
        
        Executes a step and updates the state.
    
    .EXAMPLE
        $success = Invoke-StepperStep -Step $stepDef -State $state -AllResults $allResults
        
        Executes a step that needs access to previous results.
    
    .NOTES
        Results are automatically added to the state object.
        Duration is tracked automatically.
        Errors are caught and logged in the state.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Step,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AllResults = @{}
    )
    
    $stepName = $Step.Name
    $startTime = Get-Date
    
    Write-Verbose "Executing step: $stepName"
    
    try {
        # Execute the step's script block
        # Check if step needs access to all results (using AcceptsAllResults property from config)
        $result = if ($Step.AcceptsAllResults -eq $true) {
            Write-Verbose "Step accepts AllResults parameter, passing previous results"
            & $Step.ScriptBlock -AllResults $AllResults
        } else {
            Write-Verbose "Step does not accept AllResults, executing directly"
            & $Step.ScriptBlock
        }
        
        $duration = (Get-Date) - $startTime
        
        # Record the result
        $State.StepResults[$stepName] = @{
            Status = 'Completed'
            CompletedAt = Get-Date -Format 'o'
            Duration = "$([math]::Round($duration.TotalSeconds, 2))s"
            Result = $result
        }
        
        # Mark as completed
        if ($State.CompletedSteps -notcontains $stepName) {
            $State.CompletedSteps += $stepName
        }
        
        Write-Host "`n  ✓ Step completed successfully in $([math]::Round($duration.TotalSeconds, 2))s" -ForegroundColor Green
        Write-Verbose "Step '$stepName' completed successfully"
        
        return $true
    } catch {
        $duration = (Get-Date) - $startTime
        
        # Record the failure
        $State.StepResults[$stepName] = @{
            Status = 'Failed'
            FailedAt = Get-Date -Format 'o'
            Duration = "$([math]::Round($duration.TotalSeconds, 2))s"
            Error = $_.Exception.Message
            ErrorDetails = $_.ScriptStackTrace
        }
        
        Write-Host "`n  ✗ Step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "     $($_.ScriptStackTrace)" -ForegroundColor DarkRed
        Write-Verbose "Step '$stepName' failed: $($_.Exception.Message)"
        
        return $false
    }
}
