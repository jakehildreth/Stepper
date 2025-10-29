<#
.SYNOPSIS
    Step 2: Analyze system performance

.DESCRIPTION
    Analyzes system performance based on the system information from Step 1.
    Returns performance metrics that will be used in Step 3.

.PARAMETER StepName
    Name of this step

.PARAMETER StepOrder
    Order of this step in the sequence

.PARAMETER AllResults
    Array of results from all previous steps. 
    AllResults[1] contains Step 1 results.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StepName = "Analyze-Performance",

    [Parameter(Mandatory = $false)]
    [int]$StepOrder = 2,

    [Parameter(Mandatory = $false)]
    [array]$AllResults
)

Write-Host "`n==================================="
Write-Host "Step $StepOrder : $StepName"
Write-Host "==================================="

# Get Step 1 results
$systemInfo = $AllResults[1]

Write-Host "`nReceived data from Step 1:" -ForegroundColor Cyan
Write-Host "  OS: $($systemInfo.OS.Name)"
Write-Host "  CPU Cores: $($systemInfo.CPU.PhysicalCores)"
Write-Host "  Memory: $($systemInfo.MemoryGB) GB"

Write-Host "`nAnalyzing system performance..." -ForegroundColor Cyan

# Perform analysis based on system specs
$cpuScore = switch ($systemInfo.CPU.PhysicalCores) {
    {$_ -ge 8} { "Excellent"; break }
    {$_ -ge 4} { "Good"; break }
    {$_ -ge 2} { "Fair"; break }
    default { "Poor" }
}

$memoryScore = switch ($systemInfo.MemoryGB) {
    {$_ -ge 16} { "Excellent"; break }
    {$_ -ge 8} { "Good"; break }
    {$_ -ge 4} { "Fair"; break }
    default { "Poor" }
}

# Calculate overall performance rating
$overallRating = if ($cpuScore -eq "Excellent" -and $memoryScore -eq "Excellent") {
    "High Performance"
} elseif ($cpuScore -in @("Good", "Excellent") -and $memoryScore -in @("Good", "Excellent")) {
    "Medium Performance"
} else {
    "Low Performance"
}

Write-Host "`n--- Performance Analysis ---"
Write-Host "CPU Rating: $cpuScore" -ForegroundColor $(if ($cpuScore -eq "Excellent") { "Green" } elseif ($cpuScore -eq "Good") { "Yellow" } else { "Red" })
Write-Host "Memory Rating: $memoryScore" -ForegroundColor $(if ($memoryScore -eq "Excellent") { "Green" } elseif ($memoryScore -eq "Good") { "Yellow" } else { "Red" })
Write-Host "Overall Rating: $overallRating" -ForegroundColor $(if ($overallRating -eq "High Performance") { "Green" } elseif ($overallRating -eq "Medium Performance") { "Yellow" } else { "Red" })

# Create result object
$result = @{
    CPUScore = $cpuScore
    MemoryScore = $memoryScore
    OverallRating = $overallRating
    AnalysisTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Recommendations = @()
}

# Add recommendations based on analysis
if ($cpuScore -in @("Fair", "Poor")) {
    $result.Recommendations += "Consider upgrading CPU for better performance"
}
if ($memoryScore -in @("Fair", "Poor")) {
    $result.Recommendations += "Consider adding more RAM for better performance"
}
if ($result.Recommendations.Count -eq 0) {
    $result.Recommendations += "System is performing well, no immediate upgrades needed"
}

Write-Host "`nRecommendations:"
foreach ($rec in $result.Recommendations) {
    Write-Host "  - $rec" -ForegroundColor Cyan
}

Write-Host "`nStep completed successfully!" -ForegroundColor Green
Write-Host "Performance data will be passed to Step 3." -ForegroundColor Yellow

return $result
