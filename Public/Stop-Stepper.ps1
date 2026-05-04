function Stop-Stepper {
    <#
    .SYNOPSIS
        Stops Stepper and clears the state file for the calling script.

    .DESCRIPTION
        Removes the state file, typically called at the end of a script
        when it completes successfully. This ensures the next run starts fresh.

    .EXAMPLE
        # At the end of your script:
        New-Step { Write-Host "Final step" }
        Stop-Stepper

    .NOTES
        This function automatically determines which script called it and
        removes the corresponding state file.
    #>
    [CmdletBinding()]
    param()

    # Inherit verbose preference by walking the call stack
    $callStack = Get-PSCallStack
    foreach ($frame in $callStack) {
        if ($frame.InvocationInfo.BoundParameters.ContainsKey('Verbose') -and
            $frame.InvocationInfo.BoundParameters['Verbose']) {
            $VerbosePreference = 'Continue'
            break
        }
    }

    Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] All steps complete. Cleaning up..."

    try {
        $callStack = Get-PSCallStack
        $scriptPath = $null

        # Find the calling script (skip this function)
        for ($i = 1; $i -lt $callStack.Count; $i++) {
            $frame = $callStack[$i]
            $candidatePath = $frame.ScriptName

            # Skip frames without a script name
            if (-not $candidatePath) {
                continue
            }

            # Skip frames from within the Stepper module
            # Normalize path for cross-platform comparison
            $normalizedPath = $candidatePath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
            $sep = [System.IO.Path]::DirectorySeparatorChar
            if ($normalizedPath -like '*Stepper.psm1' -or
                $normalizedPath -like "*${sep}Private${sep}*.ps1" -or
                $normalizedPath -like "*${sep}Public${sep}*.ps1") {
                continue
            }

            # Found a user script - use it
            $scriptPath = $candidatePath
            break
        }

        # If we didn't find a script in the call stack, try to get it from the calling scope's __StepperExecutionState
        if (-not $scriptPath) {
            $callingScope = $PSCmdlet.SessionState
            try {
                $executionState = $callingScope.PSVariable.Get('__StepperExecutionState')
                if ($executionState -and $executionState.Value.CurrentScriptPath) {
                    $scriptPath = $executionState.Value.CurrentScriptPath
                    Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Retrieved script path from execution state"
                }
            } catch {
                # Ignore - we'll handle the missing path below
            }
        }

        if ($scriptPath) {
            # Read log config from execution state before removing state
            $logPath = $null
            try {
                $callingScope = $PSCmdlet.SessionState
                $execState = $callingScope.PSVariable.Get('__StepperExecutionState')
                if ($execState -and $execState.Value -and $execState.Value.LogPath) {
                    $logPath = $execState.Value.LogPath
                }
            } catch {
                # Ignore; log path optional
            }

            $statePath = Get-StepperStatePath -ScriptPath $scriptPath
            Write-StepperLog -Message "All steps complete. State file removed." -LogPath $logPath
            Remove-StepperState -StatePath $statePath
            $scriptName = Split-Path $scriptPath -Leaf
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleared Stepper state for $scriptName"
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleanup complete!"
        } else {
            Write-Warning "Unable to determine calling script from call stack"
        }
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Failed to clear Stepper state: $($_.Exception.Message)", $_.Exception),
                'StepperStateRemovalFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $null
            )
        )
    }
}
