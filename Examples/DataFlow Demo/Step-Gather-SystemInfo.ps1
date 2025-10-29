<#
.SYNOPSIS
    Step 1: Gather system information

.DESCRIPTION
    Collects basic system information including OS, CPU, and Memory.
    Returns a hashtable that will be passed to subsequent steps.

.PARAMETER StepName
    Name of this step

.PARAMETER StepOrder
    Order of this step in the sequence
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StepName = "Gather-SystemInfo",

    [Parameter(Mandatory = $false)]
    [int]$StepOrder = 1
)

Write-Host "`n==================================="
Write-Host "Step $StepOrder : $StepName"
Write-Host "==================================="

Write-Host "`nCollecting system information..." -ForegroundColor Cyan

# Gather OS Information
$os = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
} elseif ($IsMacOS) {
    [PSCustomObject]@{
        Caption = "macOS"
        Version = (sw_vers -productVersion)
        BuildNumber = (sw_vers -buildVersion)
    }
} else {
    [PSCustomObject]@{
        Caption = "Linux"
        Version = (uname -r)
        BuildNumber = "N/A"
    }
}

# Gather CPU Information
$cpu = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
} elseif ($IsMacOS) {
    [PSCustomObject]@{
        Name = (sysctl -n machdep.cpu.brand_string)
        NumberOfCores = [int](sysctl -n hw.physicalcpu)
        NumberOfLogicalProcessors = [int](sysctl -n hw.logicalcpu)
    }
} else {
    [PSCustomObject]@{
        Name = (grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        NumberOfCores = (grep -c "processor" /proc/cpuinfo)
        NumberOfLogicalProcessors = (grep -c "processor" /proc/cpuinfo)
    }
}

# Gather Memory Information (in GB)
$memoryGB = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    $mem = Get-CimInstance -ClassName Win32_ComputerSystem
    [math]::Round($mem.TotalPhysicalMemory / 1GB, 2)
} elseif ($IsMacOS) {
    $memBytes = sysctl -n hw.memsize
    [math]::Round([double]$memBytes / 1GB, 2)
} else {
    $memKB = (grep MemTotal /proc/meminfo | awk '\''{print $2}'\'')
    [math]::Round([double]$memKB / 1MB, 2)
}

Write-Host "`n--- System Information ---"
Write-Host "OS: $($os.Caption) $($os.Version)" -ForegroundColor Green
Write-Host "CPU: $($cpu.Name)" -ForegroundColor Green
Write-Host "Cores: $($cpu.NumberOfCores) physical, $($cpu.NumberOfLogicalProcessors) logical" -ForegroundColor Green
Write-Host "Memory: $memoryGB GB" -ForegroundColor Green

# Create result object to pass to next steps
$result = @{
    OS = @{
        Name = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
    }
    CPU = @{
        Name = $cpu.Name
        PhysicalCores = $cpu.NumberOfCores
        LogicalProcessors = $cpu.NumberOfLogicalProcessors
    }
    MemoryGB = $memoryGB
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

Write-Host "`nStep completed successfully!" -ForegroundColor Green
Write-Host "Data will be passed to subsequent steps." -ForegroundColor Yellow

return $result
