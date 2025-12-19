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

        # Find the calling script (skip this function)
        for ($i = 1; $i -lt $callStack.Count; $i++) {
            $frame = $callStack[$i]
            $scriptPath = $frame.ScriptName

            # Skip frames without a script name
            if (-not $scriptPath) {
                continue
            }

            # Skip frames from within the Stepper module
            if ($scriptPath -like '*Stepper.psm1' -or
                $scriptPath -like '*\Private\*.ps1' -or
                $scriptPath -like '*\Public\*.ps1') {
                continue
            }

            # Found the user's script
            $statePath = Get-StepperStatePath -ScriptPath $scriptPath
            Remove-StepperState -StatePath $statePath
            $scriptName = Split-Path $scriptPath -Leaf
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleared Stepper state for $scriptName"

            # Also remove the persisted $Stepper data file
            $stepperDataPath = Join-Path -Path (Split-Path $statePath -Parent) -ChildPath "stepper-data.xml"
            if (Test-Path $stepperDataPath) {
                Remove-Item $stepperDataPath -Force -ErrorAction SilentlyContinue
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleared persisted `$Stepper data"
            }

            # Clear the session state
            if ($script:StepperSessionState) {
                $script:StepperSessionState = $null
            }

            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Cleanup complete!"

            return
        }

        Write-Warning "Unable to determine calling script from call stack"
    }
    catch {
        Write-Error "Failed to clear Stepper state: $_"
    }
}
