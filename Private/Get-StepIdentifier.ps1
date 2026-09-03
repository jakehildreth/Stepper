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

    $callStack = Get-PSCallStack

    # Walk up the call stack to find the first non-module caller
    # Stack typically looks like: [0]=Get-StepIdentifier, [1]=New-Step, [2]=UserScript
    for ($i = 0; $i -lt $callStack.Count; $i++) {
        $frame = $callStack[$i]
        $scriptName = $frame.ScriptName

        # Skip frames without a script name
        if (-not $scriptName) {
            continue
        }

        # Skip frames from the Stepper module, whether loaded from the source repo,
        # a built artefact, or an installed module copy. The module file is always
        # named Stepper.psm1 and its functions live under a Stepper/Private or
        # Stepper/Public directory; matching on the path shape (not the source repo
        # location) ensures built/installed copies are also recognized as module
        # frames and never mistaken for the user's script.
        $stepperDir = Split-Path -Path $PSScriptRoot -Parent
        # Normalize paths for cross-platform comparison
        $normalizedScript = $scriptName -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $normalizedStepperDir = $stepperDir -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $sep = [System.IO.Path]::DirectorySeparatorChar

        $isModulePsm1   = $normalizedScript -like "*${sep}Stepper.psm1"
        $isModuleFolder = $normalizedScript -like "*${sep}Stepper${sep}Private${sep}*" -or
                          $normalizedScript -like "*${sep}Stepper${sep}Public${sep}*"
        $isSourceRepo   = $normalizedScript -like "$normalizedStepperDir${sep}Private${sep}*" -or
                          $normalizedScript -like "$normalizedStepperDir${sep}Public${sep}*"

        if ($isModulePsm1 -or $isModuleFolder -or $isSourceRepo) {
            continue
        }

        # This is the user's script - return its location
        $line = $frame.ScriptLineNumber
        return "${scriptName}:${line}"
    }

    $exception = [System.InvalidOperationException]::new('Unable to determine step identifier from call stack')
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'StepIdentifierNotDetermined',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $callStack
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
