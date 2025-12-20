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
    Write-Warning "Non-resumable code detected in ${ScriptName}:"
    foreach ($lineNum in $blockLineNums) {
        $lineContent = $ScriptLines[$lineNum - 1].Trim()
        Write-Host "  ${lineNum}: $lineContent" -ForegroundColor Gray
    }
    Write-Host "This code will re-execute on every run, including resumed runs." -ForegroundColor Yellow
    Write-Host ""

    if ($hasStepperVar) {
        Write-Warning "This code references `$Stepper variables!"
    }

    Write-Host "How would you like to handle this?" -ForegroundColor Cyan
    Write-Host "  [W] Wrap in New-Step block" -ForegroundColor White
    if ($Block.IsBeforeStop) {
        Write-Host "  [M] Move after Stop-Stepper" -ForegroundColor White
    }
    if ($hasStepperVar) {
        Write-Host "  [D] Delete this code (WARNING: This will delete code that uses `$Stepper variables)" -ForegroundColor White
    } else {
        Write-Host "  [D] Delete this code" -ForegroundColor White
    }
    Write-Host "  [I] Ignore and continue (Default)" -ForegroundColor Cyan
    Write-Host "  [Q] Quit" -ForegroundColor White
    Write-Host ""

    if ($Block.IsBeforeStop) {
        Write-Host "Choice [w/m/d/" -NoNewline
        Write-Host "I" -NoNewline -ForegroundColor Cyan
        Write-Host "/q]: " -NoNewline
    } else {
        Write-Host "Choice [w/d/" -NoNewline
        Write-Host "I" -NoNewline -ForegroundColor Cyan
        Write-Host "/q]: " -NoNewline
    }
    $choice = Read-Host

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
        'q' { return 'Quit' }
        default { return 'Ignore' }
    }
}
