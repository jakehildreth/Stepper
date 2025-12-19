function Get-NonResumableCodeAction {
    <#
    .SYNOPSIS
        Prompts user for action on a non-resumable code block.

    .PARAMETER ScriptName
        Name of the script file.

    .PARAMETER ScriptLines
        Array of script lines.

    .PARAMETER Block
        Code block with Lines and IsBeforeStop properties.

    .OUTPUTS
        String with chosen action: 'Wrap', 'Move', 'Delete', or 'Ignore'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScriptLines,

        [Parameter(Mandatory)]
        [hashtable]$Block
    )

    $blockLineNums = $Block.Lines | ForEach-Object { $_ + 1 }  # Convert to 1-based
    $blockCode = $Block.Lines | ForEach-Object { $ScriptLines[$_].Trim() }
    $hasStepperVar = ($blockCode -join ' ') -match '\$Stepper\.'

    Write-Host ""
    Write-Host "Non-resumable code detected in ${ScriptName}:" -ForegroundColor Yellow
    foreach ($lineNum in $blockLineNums) {
        $lineContent = $ScriptLines[$lineNum - 1].Trim()
        Write-Host "  Line ${lineNum}: $lineContent" -ForegroundColor Gray
    }
    Write-Host "This code will re-execute on every run, including resumed runs." -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow

    if ($hasStepperVar) {
        Write-Host "⚠️  This code references" -NoNewline -ForegroundColor Red
        Write-Host " `$Stepper " -NoNewline -ForegroundColor Yellow
        Write-Host "variables!" -ForegroundColor Red
    }

    Write-Host "How would you like to fix this?" -ForegroundColor Cyan
    Write-Host "  [W] Wrap in New-Step block" -ForegroundColor White
    if ($Block.IsBeforeStop) {
        Write-Host "  [M] Move after Stop-Stepper" -ForegroundColor White
    }
    Write-Host "  [D] Delete this code" -ForegroundColor White
    if ($hasStepperVar) {
        Write-Host "      (Warning: This will delete code that uses " -NoNewline -ForegroundColor DarkYellow
        Write-Host "`$Stepper" -NoNewline -ForegroundColor Yellow
        Write-Host " variables)" -ForegroundColor DarkYellow
    }
    Write-Host "  [I] Ignore (continue anyway)" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "Choice"

    switch ($choice.ToLower()) {
        'w' { return 'Wrap' }
        'm' {
            if ($Block.IsBeforeStop) {
                return 'Move'
            } else {
                return 'Ignore'
            }
        }
        'd' { return 'Delete' }
        default { return 'Ignore' }
    }
}
