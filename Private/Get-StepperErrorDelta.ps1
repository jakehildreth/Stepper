function Get-StepperErrorDelta {
    <#
    .SYNOPSIS
        Returns the errors added to $Error after a baseline record.

    .DESCRIPTION
        $Error lists the newest error first. This function walks $Error from the
        newest record down to the baseline record (exclusive) and returns what it
        passed. With a null baseline, every record in $Error is returned. If the
        baseline has been pushed out of $Error (see $MaximumErrorCount), every
        record in $Error is returned.

    .PARAMETER Baseline
        The newest record in $Error before the work started, or $null when $Error was empty.

    .OUTPUTS
        System.Management.Automation.ErrorRecord[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Baseline
    )

    $delta = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $global:Error) {
        if ([object]::ReferenceEquals($record, $Baseline)) {
            break
        }
        $delta.Add($record)
    }
    $delta.ToArray()
}
