function Get-StepIdentifier {
    <#
    .SYNOPSIS
        Gets a unique identifier for the current step based on caller location.

    .DESCRIPTION
        Analyzes the call stack to find the script and line number where New-Step was called.
        Returns an identifier in the format "filepath:line".

    .OUTPUTS
        System.String - Step identifier (e.g., "C:\script.ps1:42")
    #>
    [CmdletBinding()]
    param()

    # Get the call stack to trace back to the user's script
    # Call stack is like a breadcrumb trail showing: Get-StepIdentifier -> New-Step -> User's Script
    $callStack = Get-PSCallStack

    # Walk up the call stack to find the first non-module caller
    # Stack typically looks like: [0]=Get-StepIdentifier, [1]=New-Step, [2]=UserScript
    # We skip internal Stepper module frames to find where the user called New-Step
    for ($i = 0; $i -lt $callStack.Count; $i++) {
        $frame = $callStack[$i]
        $scriptName = $frame.ScriptName

        # Skip frames without a script name (interactive console, etc.)
        if (-not $scriptName) {
            continue
        }

        # Skip frames from the Stepper module directory
        # We only want to identify the user's script, not internal module code
        $stepperDir = Split-Path -Path $PSScriptRoot -Parent
        # Normalize paths for cross-platform comparison (Windows uses \, Linux/Mac use /)
        $normalizedScript = $scriptName -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $normalizedStepperDir = $stepperDir -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar

        # Skip if it's from the module's Private/Public folders or the main PSM1
        # This filters out all internal Stepper code to find the actual user script
        if ($normalizedScript -like "$normalizedStepperDir$([System.IO.Path]::DirectorySeparatorChar)Private$([System.IO.Path]::DirectorySeparatorChar)*" -or
            $normalizedScript -like "$normalizedStepperDir$([System.IO.Path]::DirectorySeparatorChar)Public$([System.IO.Path]::DirectorySeparatorChar)*" -or
            $normalizedScript -like "$normalizedStepperDir$([System.IO.Path]::DirectorySeparatorChar)Stepper.psm1" -or
            $normalizedScript -like "*$([System.IO.Path]::DirectorySeparatorChar)Modules$([System.IO.Path]::DirectorySeparatorChar)Stepper$([System.IO.Path]::DirectorySeparatorChar)*") {
            continue
        }

        # This is the user's script - return its location as "path:line"
        # This unique identifier is used to track which step completed
        $line = $frame.ScriptLineNumber
        return "${scriptName}:${line}"
    }

    throw "Unable to determine step identifier from call stack"
}
