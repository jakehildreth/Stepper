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
        String with chosen action: 'Wrap', 'MarkIgnored', 'Delete', or 'Ignore'.
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
    Write-Host "[!] Non-resumable code detected in ${ScriptName}." -ForegroundColor Magenta
    Write-Host "    This code will execute on every run of this script, including resumed runs:" -ForegroundColor Magenta
    foreach ($lineNum in $blockLineNums) {
        $lineContent = $ScriptLines[$lineNum - 1].Trim()
        Write-Host "  ${lineNum}: $lineContent" -ForegroundColor Gray
    }
    Write-Host ""

    Write-Host "How would you like to handle this?"
    Write-Host ""
    Write-Host "  [W] Wrap in New-Step block (Default)" -ForegroundColor Cyan
    Write-Host "  [M] Mark as expected to ignore this code on future script runs" -ForegroundColor White
    Write-Host "  [D] Delete this code" -ForegroundColor White
    if ($hasStepperVar) {
        Write-Host "      WARNING: Because this code references `$Stepper variables," -ForegroundColor Yellow
        Write-Host "               deleting it may impact functionality." -ForegroundColor Yellow
    }
    Write-Host "  [I] Ignore and continue" -ForegroundColor White
    Write-Host "  [Q] Quit" -ForegroundColor White
    Write-Host ""

    Write-Host "Choice? [" -NoNewline
    Write-Host "W" -NoNewline -ForegroundColor Cyan
    Write-Host "/m/d/i/q]: " -NoNewline
    $choice = Read-Host

    switch ($choice.ToLower()) {
        'w' { return 'Wrap' }
        '' { return 'Wrap' }  # Default to Wrap
        'm' { return 'MarkIgnored' }
        'd' { return 'Delete' }
        'i' { return 'Ignore' }
        'q' { return 'Quit' }
        default { return 'Wrap' }  # Default to Wrap
    }
}
