function Clear-StepperSession {
    <#
    .SYNOPSIS
        Resets all Stepper session state for a pristine fresh start.

    .DESCRIPTION
        Removes the $Stepper variable from the caller's scope (so a new run
        starts with no data from any previous run), clears a stale
        __StepperInitialized sentinel so the next New-Step call runs the
        first-run block, deletes the state file, and returns the execution
        state to fresh-run defaults so no log config from a previous run
        carries over.

        Called by every fresh-start branch in New-Step (all Start Over menu
        choices and the automatic fresh start after all steps complete).

    .PARAMETER StatePath
        The path to the state file to delete.

    .PARAMETER CallingScope
        The caller's session state (pass $PSCmdlet.SessionState from the
        calling advanced function).

    .PARAMETER ExecutionState
        The live execution state hashtable to reset to fresh-run defaults.

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath,

        [Parameter(Mandatory)]
        [System.Management.Automation.SessionState]$CallingScope,

        [Parameter(Mandatory)]
        [hashtable]$ExecutionState
    )

    # Remove $Stepper so no data from a previous run survives, regardless of
    # how it got into the caller's scope
    try {
        $CallingScope.PSVariable.Remove('Stepper')
    } catch {
        # Best effort: New-Step recreates $Stepper on the next step
    }

    # Reset execution state to fresh-run defaults: no resume, no inherited log config
    $ExecutionState.RestoreMode    = $false
    $ExecutionState.TargetStep     = $null
    $ExecutionState.LogPath        = $null
    $ExecutionState.LoggingEnabled = $true
    $ExecutionState.NoLogStepIds   = @()

    # Delete the state file
    Remove-StepperState -StatePath $StatePath
}
