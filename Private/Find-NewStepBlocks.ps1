function Find-NewStepBlocks {
    <#
    .SYNOPSIS
        Finds all New-Step blocks and Stop-Stepper line in a script using the PowerShell AST.

    .DESCRIPTION
        Parses the script via [System.Management.Automation.Language.Parser] and queries the
        resulting AST for CommandAst nodes whose command name is 'New-Step' or 'Stop-Stepper'.
        This correctly handles multi-line scriptblocks, braces inside strings/heredocs, and
        New-Step/Stop-Stepper text inside comments or string literals.

        Returned Start/End indices are 0-based (AST 1-based line numbers minus 1) so callers
        can index directly into a Get-Content array.

    .PARAMETER ScriptPath
        Path to the script file to analyze. Uses Get-ScriptAst (with caching).

    .PARAMETER ScriptContent
        Raw script content as a string. Used by tests to avoid temp files. Parsed via
        [Parser]::ParseInput() without caching.

    .OUTPUTS
        Hashtable with:
          NewStepBlocks: array of @{ Start; End } (0-based line indices)
          StopStepperLine: 0-based line index of Stop-Stepper, or -1 if absent
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(ParameterSetName = 'Content', Mandatory)]
        [AllowEmptyString()]
        [string]$ScriptContent
    )

    $newStepBlocks = @()
    $stopStepperLine = -1

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $parsed = Get-ScriptAst -ScriptPath $ScriptPath
        $ast = $parsed.Ast
    } else {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$tokens, [ref]$errors)
    }

    # Find all New-Step command calls. AST correctly ignores occurrences inside strings/comments
    $newStepCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'New-Step'
    }, $true)

    foreach ($call in $newStepCalls) {
        # Convert 1-based AST line numbers to 0-based array indices
        $newStepBlocks += @{
            Start = $call.Extent.StartLineNumber - 1
            End   = $call.Extent.EndLineNumber - 1
        }
    }

    # Find Stop-Stepper, take the first occurrence
    $stopCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'Stop-Stepper'
    }, $true)

    if ($stopCalls -and $stopCalls.Count -gt 0) {
        $firstStop = ($stopCalls | Sort-Object { $_.Extent.StartLineNumber })[0]
        $stopStepperLine = $firstStop.Extent.StartLineNumber - 1

        # Exclude any New-Step blocks that start after Stop-Stepper
        $newStepBlocks = @($newStepBlocks | Where-Object { $_.Start -lt $stopStepperLine })
    }

    return @{
        NewStepBlocks   = $newStepBlocks
        StopStepperLine = $stopStepperLine
    }
}
