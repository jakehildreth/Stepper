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
    # This allows -Verbose to propagate from the parent script to this function
    # even when not explicitly passed as a parameter
    $callStack = Get-PSCallStack
    foreach ($frame in $callStack) {
        # Check each frame in the call stack for the Verbose parameter
        if ($frame.InvocationInfo.BoundParameters.ContainsKey('Verbose') -and
            $frame.InvocationInfo.BoundParameters['Verbose']) {
            # Enable verbose output for this function
            $VerbosePreference = 'Continue'
            break
        }
    }

    Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] All steps complete. Cleaning up..."

    try {
        # Get the call stack to find which script called Stop-Stepper
        # The call stack is a list of all active function/script calls
        $callStack = Get-PSCallStack

        # Find the calling script (skip this function itself at index 0)
        # We walk up the stack to find the user's script, not internal module code
        for ($i = 1; $i -lt $callStack.Count; $i++) {
            $frame = $callStack[$i]
            $scriptPath = $frame.ScriptName

            # Skip frames without a script name (interactive console, etc.)
            if (-not $scriptPath) {
                continue
            }

            # Skip frames from within the Stepper module itself
            # We only want to find the user's script that imported/used Stepper
            # Normalize path for cross-platform comparison (handles Windows/Linux path separators)
            $normalizedPath = $scriptPath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
            $sep = [System.IO.Path]::DirectorySeparatorChar
            # Check if the path is part of the Stepper module
            if ($normalizedPath -like '*Stepper.psm1' -or
                $normalizedPath -like "*${sep}Private${sep}*.ps1" -or
                $normalizedPath -like "*${sep}Public${sep}*.ps1") {
                continue
            }

            # Found the user's script - now clean up its state
            $statePath = Get-StepperStatePath -ScriptPath $scriptPath
            Remove-StepperState -StatePath $statePath
            $scriptName = Split-Path $scriptPath -Leaf
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleared Stepper state for $scriptName"

            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleanup complete!"

            return
        }

        Write-Warning "Unable to determine calling script from call stack"
    }
    catch {
        Write-Error "Failed to clear Stepper state: $_"
    }
}
