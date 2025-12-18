function New-Substep {
    <#
    .SYNOPSIS
        Executes a substep within a New-Step block for better organization.
    
    .DESCRIPTION
        New-Substep provides a way to organize and label sub-tasks within a step.
        Substeps are not tracked individually in the state file - they are part of
        their parent step. If a step is resumed or skipped, all its substeps are
        included in that action.
    
    .PARAMETER ScriptBlock
        The code to execute for this substep.
    
    .PARAMETER Name
        Optional name/description for the substep to display during execution.
    
    .EXAMPLE
        New-Step {
            Write-Host "Setting up environment"
            
            New-Substep -Name "Installing dependencies" {
                Install-Module -Name SomeModule
            }
            
            New-Substep -Name "Configuring settings" {
                Set-Config -Key "Value"
            }
        }
    
    .NOTES
        Substeps are purely organizational and do not affect state tracking or resume behavior.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Position = 1)]
        [string]$Name
    )
    
    if ($Name) {
        Write-Host "  → $Name" -ForegroundColor DarkGray
    }
    
    try {
        & $ScriptBlock
    }
    catch {
        if ($Name) {
            Write-Error "Substep '$Name' failed: $_"
        } else {
            Write-Error "Substep failed: $_"
        }
        throw
    }
}
