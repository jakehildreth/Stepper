<#
.SYNOPSIS
    Step 3: Generate comprehensive report

.DESCRIPTION
    Generates a final report using data from both Step 1 (system info) and Step 2 (performance analysis).
    Demonstrates receiving data from multiple previous steps.

.PARAMETER StepName
    Name of this step

.PARAMETER StepOrder
    Order of this step in the sequence

.PARAMETER AllResults
    Array of all previous step results.
    AllResults[1] contains Step 1 results.
    AllResults[2] contains Step 2 results.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StepName = "Generate-Report",

    [Parameter(Mandatory = $false)]
    [int]$StepOrder = 3,

    [Parameter(Mandatory = $false)]
    [array]$AllResults
)

Write-Host "`n==================================="
Write-Host "Step $StepOrder : $StepName"
Write-Host "==================================="

Write-Host "`nGenerating comprehensive report..." -ForegroundColor Cyan

# Extract results from previous steps using intuitive indexing
$systemInfo = $AllResults[1]  # Step 1 results
$performanceAnalysis = $AllResults[2]  # Step 2 results

Write-Host "`nReceived data from previous steps:"
Write-Host "  AllResults[1] (Step 1): OS, CPU, Memory details"
Write-Host "  AllResults[2] (Step 2): Performance ratings and recommendations"

# Generate report
Write-Host ""
Write-Host ("=" * 70)
Write-Host "               SYSTEM HEALTH REPORT"
Write-Host ("=" * 70)

Write-Host "`n--- SYSTEM INFORMATION ---"
Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Scan Started: $($systemInfo.Timestamp)"
Write-Host ""
Write-Host "Operating System:"
Write-Host "  Name:    $($systemInfo.OS.Name)"
Write-Host "  Version: $($systemInfo.OS.Version)"
Write-Host "  Build:   $($systemInfo.OS.BuildNumber)"
Write-Host ""
Write-Host "Processor:"
Write-Host "  Model:             $($systemInfo.CPU.Name)"
Write-Host "  Physical Cores:    $($systemInfo.CPU.PhysicalCores)"
Write-Host "  Logical Processors: $($systemInfo.CPU.LogicalProcessors)"
Write-Host ""
Write-Host "Memory:"
Write-Host "  Total RAM: $($systemInfo.MemoryGB) GB"

Write-Host "`n--- PERFORMANCE ANALYSIS ---"
Write-Host "Analysis Completed: $($performanceAnalysis.AnalysisTimestamp)"
Write-Host ""
Write-Host "Performance Ratings:"
Write-Host "  CPU Performance:    $($performanceAnalysis.CPUScore)" -ForegroundColor $(if ($performanceAnalysis.CPUScore -eq "Excellent") { "Green" } elseif ($performanceAnalysis.CPUScore -eq "Good") { "Yellow" } else { "Red" })
Write-Host "  Memory Performance: $($performanceAnalysis.MemoryScore)" -ForegroundColor $(if ($performanceAnalysis.MemoryScore -eq "Excellent") { "Green" } elseif ($performanceAnalysis.MemoryScore -eq "Good") { "Yellow" } else { "Red" })
Write-Host "  Overall Rating:     $($performanceAnalysis.OverallRating)" -ForegroundColor $(if ($performanceAnalysis.OverallRating -eq "High Performance") { "Green" } elseif ($performanceAnalysis.OverallRating -eq "Medium Performance") { "Yellow" } else { "Red" })

Write-Host "`n--- RECOMMENDATIONS ---"
foreach ($rec in $performanceAnalysis.Recommendations) {
    Write-Host "  • $rec" -ForegroundColor Cyan
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "                    END OF REPORT"
Write-Host ("=" * 70)

# Create final summary
$finalResult = @{
    ReportGenerated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    SystemSummary = @{
        OS = $systemInfo.OS.Name
        CPUCores = $systemInfo.CPU.PhysicalCores
        MemoryGB = $systemInfo.MemoryGB
    }
    PerformanceSummary = @{
        OverallRating = $performanceAnalysis.OverallRating
        CPUScore = $performanceAnalysis.CPUScore
        MemoryScore = $performanceAnalysis.MemoryScore
    }
    RecommendationCount = $performanceAnalysis.Recommendations.Count
}

Write-Host "`nStep completed successfully!" -ForegroundColor Green
Write-Host "Final report has been generated using data from all previous steps." -ForegroundColor Yellow

return $finalResult
