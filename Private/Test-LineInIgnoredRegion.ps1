function Test-LineInIgnoredRegion {
    <#
    .SYNOPSIS
        Checks if a line is within a Stepper ignore region.

    .PARAMETER LineIndex
        The zero-based line index to check.

    .PARAMETER IgnoredRegions
        Array of hashtables with Start and End properties marking ignored regions.

    .OUTPUTS
        Boolean - True if the line is in an ignored region, false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$LineIndex,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$IgnoredRegions
    )

    # Check if the line falls within any ignored region
    # Ignored regions are marked with #region Stepper ignore / #endregion Stepper ignore
    foreach ($region in $IgnoredRegions) {
        # Use zero-based indexing to check if line is within region boundaries
        if ($LineIndex -ge $region.Start -and $LineIndex -le $region.End) {
            return $true
        }
    }
    # Line is not in any ignored region
    return $false
}
