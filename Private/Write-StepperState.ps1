function Write-StepperState {
    <#
    .SYNOPSIS
        Writes the Stepper state file.
    
    .DESCRIPTION
        Serializes and writes the state object to disk.
    
    .PARAMETER StatePath
        The path to the state file.
    
    .PARAMETER ScriptHash
        SHA256 hash of the script content.
    
    .PARAMETER LastCompletedStep
        Identifier of the last successfully completed step (format: "filepath:line").
    
    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath,
        
        [Parameter(Mandatory)]
        [string]$ScriptHash,
        
        [Parameter(Mandatory)]
        [string]$LastCompletedStep
    )
    
    $state = [PSCustomObject]@{
        ScriptHash        = $ScriptHash
        LastCompletedStep = $LastCompletedStep
        Timestamp         = (Get-Date).ToString('o')
    }
    
    try {
        $json = ConvertTo-Json -InputObject $state -Depth 10
        Set-Content -Path $StatePath -Value $json -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write state file '$StatePath': $_"
    }
}
