$script:astCache = @{}

function Get-ScriptAst {
    <#
    .SYNOPSIS
        Parses a PowerShell script file and returns its AST, token stream, and parse errors.

    .DESCRIPTION
        Wraps [System.Management.Automation.Language.Parser]::ParseFile() with a module-scoped
        cache keyed on "$ScriptPath:$hash". Callers that invoke Get-ScriptAst multiple times for
        the same unmodified script file receive the cached result without re-reading from disk.

        When parse errors are present the partial AST is still returned. The caller decides
        whether to abort. Each parse error is emitted as a Write-Warning.

    .PARAMETER ScriptPath
        Absolute path to the script file to parse.

    .OUTPUTS
        PSCustomObject with properties:
          Ast: [System.Management.Automation.Language.ScriptBlockAst]
          Tokens: [System.Management.Automation.Language.Token[]]
          Errors: [System.Management.Automation.Language.ParseError[]]

    .NOTES
        Line number convention: AST Extent properties (StartLineNumber, EndLineNumber) are 1-based.
        Callers that index into a 0-based array must subtract 1 at the boundary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $scriptHash = Get-ScriptHash -ScriptPath $ScriptPath
    $cacheKey = "${ScriptPath}:${scriptHash}"

    if ($script:astCache.ContainsKey($cacheKey)) {
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Get-ScriptAst cache hit: $ScriptPath"
        return $script:astCache[$cacheKey]
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)

    foreach ($parseError in $errors) {
        Write-Warning "[Stepper] Parse error in '$ScriptPath' at line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }

    $result = [PSCustomObject]@{
        Ast    = $ast
        Tokens = $tokens
        Errors = $errors
    }

    $script:astCache[$cacheKey] = $result
    Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Get-ScriptAst parsed and cached: $ScriptPath"
    return $result
}
