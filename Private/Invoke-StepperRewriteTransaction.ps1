function Invoke-StepperRewriteTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)

    try {
        $backupPath = New-StepperBackup -Path $ScriptPath -ErrorAction Stop
        if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw "Backup was not created for '$ScriptPath'."
        }
        Set-Content -LiteralPath $ScriptPath -Value $Content -NoNewline -Force -ErrorAction Stop
        Remove-StepperState -StatePath (Get-StepperStatePath -ScriptPath $ScriptPath) -ErrorAction Stop
    }
    catch {
        $exception = [System.IO.IOException]::new("Failed to rewrite Stepper script '$ScriptPath'.", $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StepperRewriteFailed',
            [System.Management.Automation.ErrorCategory]::WriteError,
            $ScriptPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    [PSCustomObject]@{
        Changed    = $true
        BackupPath = $backupPath
    }
}
