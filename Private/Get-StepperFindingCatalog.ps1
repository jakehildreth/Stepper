function Get-StepperFindingCatalog {
    [CmdletBinding()]
    param()

    if (-not $script:StepperFindingCatalog) {
        $definitions = @(
            @('NotStepperScript', 'Error', 'None', 'The file does not contain a Stepper lifecycle command.'),
            @('ParseError', 'Error', 'None', 'PowerShell could not parse the script.'),
            @('MissingParamBlock', 'Error', 'Deterministic', 'A Stepper script requires a param block.'),
            @('MissingCmdletBinding', 'Error', 'Deterministic', 'A Stepper script requires [CmdletBinding()] on its param block.'),
            @('MissingInstallGuard', 'Error', 'Deterministic', 'The Stepper install guard is missing.'),
            @('InvalidInstallGuard', 'Error', 'None', 'The Stepper install guard does not conditionally install Stepper only when it is unavailable.'),
            @('MisplacedInstallGuard', 'Error', 'None', 'The Stepper install guard is not in the canonical bootstrap position.'),
            @('MissingBootstrapRegion', 'Error', 'Deterministic', 'The install guard is not enclosed by a paired Stepper-ignore region.'),
            @('MalformedIgnoreRegion', 'Error', 'None', 'A Stepper-ignore region is unmatched, mismatched, or nested.'),
            @('MissingStartStepper', 'Error', 'Deterministic', 'Exactly one top-level Start-Stepper or Initialize-Stepper call is required.'),
            @('DuplicateStartStepper', 'Error', 'Interactive', 'More than one Start-Stepper or Initialize-Stepper call was found.'),
            @('NestedStartStepper', 'Error', 'Interactive', 'Start-Stepper or Initialize-Stepper must be a direct root statement.'),
            @('StartOutsideBootstrapRegion', 'Error', 'Interactive', 'Start-Stepper or Initialize-Stepper must be inside the bootstrap Stepper-ignore region.'),
            @('StartBeforeInstallGuard', 'Error', 'Interactive', 'Start-Stepper or Initialize-Stepper must appear after the install guard.'),
            @('StartAfterExecutableCode', 'Error', 'Interactive', 'Start-Stepper or Initialize-Stepper must appear before managed or unmanaged executable code.'),
            @('NoSteps', 'Error', 'None', 'A Stepper script requires at least one New-Step call.'),
            @('NestedNewStep', 'Error', 'None', 'New-Step must be a direct root statement.'),
            @('MissingStepScriptBlock', 'Error', 'None', 'New-Step requires a scriptblock argument.'),
            @('NewStepBeforeStart', 'Error', 'None', 'New-Step cannot appear before Start-Stepper or Initialize-Stepper.'),
            @('NewStepAfterStop', 'Error', 'None', 'New-Step cannot appear after Stop-Stepper.'),
            @('DuplicateStopStepper', 'Error', 'None', 'More than one Stop-Stepper call was found.'),
            @('NestedStopStepper', 'Error', 'None', 'Stop-Stepper must be a direct root statement.'),
            @('ExecutableCodeAfterStop', 'Error', 'None', 'Executable user code cannot appear after Stop-Stepper.'),
            @('UnmanagedCode', 'Error', 'Interactive', 'Executable user code exists outside New-Step blocks and Stepper-ignore regions.'),
            @('MissingCbh', 'Warning', 'None', 'The script does not contain comment-based help with a .SYNOPSIS section.'),
            @('MissingStopStepper', 'Warning', 'Interactive', 'Stop-Stepper is missing; successful runs will not remove state automatically.')
        )

        $script:StepperFindingCatalog = [ordered]@{}
        foreach ($definition in $definitions) {
            $script:StepperFindingCatalog[$definition[0]] = [PSCustomObject]@{
                Code        = $definition[0]
                Severity    = $definition[1]
                Remediation = $definition[2]
                Message     = $definition[3]
            }
        }
    }

    return $script:StepperFindingCatalog
}
