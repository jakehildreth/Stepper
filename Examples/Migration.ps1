<#
.SYNOPSIS
    Migrates users from on-prem AD to Azure AD with resumable checkpoints
    
.DESCRIPTION
    Example script demonstrating Stepper module usage for a multi-step migration process.
    Data is automatically persisted between steps using Save-StepData and Get-StepData.
    
.NOTES
    Uses the Stepper module's built-in Save-StepData and Get-StepData functions.
    Data files are stored in .\data\ directory relative to this script.
#>
Import-Module "$PSScriptRoot\..\Stepper.psd1" -Force

# Configuration
$batchSize = 100

Write-Host "Starting User Migration Process" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

New-Step {
    Write-Host "Step 1: Gathering users from Active Directory..." -ForegroundColor Green
    
    # Simulate long-running AD query
    $users = Get-ADUser -Filter {Enabled -eq $true} -Properties Department, Title, Mail, Manager |
        Select-Object -First 500 |
        Select-Object SamAccountName, Name, Department, Title, Mail, @{N='Manager';E={$_.Manager}}
    
    Write-Host "  Found $($users.Count) enabled users"
    
    # Save to disk for next step
    Save-StepData $users "source-users"
    
    # Also save summary for reporting
    $summary = @{
        TotalUsers = $users.Count
        StartTime = Get-Date
        Departments = ($users.Department | Group-Object | Measure-Object).Count
    }
    Save-StepData $summary "migration-summary"
    
    Write-Host "  User data saved to disk" -ForegroundColor Gray
}

New-Step {
    Write-Host "Step 2: Validating and preparing user data..." -ForegroundColor Green
    
    # Load users from previous step
    $users = Get-StepData "source-users"
    Write-Host "  Loaded $($users.Count) users from cache"
    
    # Validate and transform data (simulate taking time)
    $validUsers = @()
    $invalidUsers = @()
    
    foreach ($user in $users) {
        Start-Sleep -Milliseconds 50  # Simulate processing time
        
        if ($user.Mail -and $user.Mail -match '^[\w\.\-]+@[\w\.\-]+\.\w+$') {
            $validUsers += [PSCustomObject]@{
                UPN = $user.Mail
                DisplayName = $user.Name
                Department = $user.Department
                JobTitle = $user.Title
                OnPremSID = $user.SamAccountName
            }
        } else {
            $invalidUsers += $user
        }
    }
    
    Write-Host "  Valid users: $($validUsers.Count)" -ForegroundColor Gray
    Write-Host "  Invalid users: $($invalidUsers.Count)" -ForegroundColor Yellow
    
    # Save results
    Save-StepData $validUsers "valid-users"
    Save-StepData $invalidUsers "invalid-users"
    
    if ($invalidUsers.Count -gt 0) {
        Write-Warning "Some users failed validation. Check .\data\invalid-users.json"
    }
}

New-Step {
    Write-Host "Step 3: Creating users in Azure AD..." -ForegroundColor Green
    
    $validUsers = Get-StepData "valid-users"
    $created = @()
    $failed = @()
    
    Write-Host "  Creating $($validUsers.Count) users in batches of $batchSize..."
    
    for ($i = 0; $i -lt $validUsers.Count; $i += $batchSize) {
        $batch = $validUsers[$i..[Math]::Min($i + $batchSize - 1, $validUsers.Count - 1)]
        Write-Host "    Processing batch $([Math]::Floor($i/$batchSize) + 1)..." -ForegroundColor Gray
        
        foreach ($user in $batch) {
            try {
                # Simulate Azure AD user creation
                Start-Sleep -Milliseconds 100
                # New-AzureADUser -UserPrincipalName $user.UPN -DisplayName $user.DisplayName ...
                
                $created += [PSCustomObject]@{
                    UPN = $user.UPN
                    DisplayName = $user.DisplayName
                    Status = "Created"
                    Timestamp = Get-Date
                }
            }
            catch {
                Write-Warning "Failed to create $($user.UPN): $_"
                $failed += [PSCustomObject]@{
                    UPN = $user.UPN
                    Error = $_.Exception.Message
                }
            }
        }
    }
    
    Write-Host "  Successfully created: $($created.Count)" -ForegroundColor Gray
    Write-Host "  Failed: $($failed.Count)" -ForegroundColor Gray
    
    Save-StepData $created "azure-users-created"
    if ($failed.Count -gt 0) {
        Save-StepData $failed "azure-users-failed"
    }
}

New-Step {
    Write-Host "Step 4: Assigning licenses..." -ForegroundColor Green
    
    $createdUsers = Get-StepData "azure-users-created"
    $licensed = @()
    
    Write-Host "  Assigning licenses to $($createdUsers.Count) users..."
    
    foreach ($user in $createdUsers) {
        try {
            # Simulate license assignment
            Start-Sleep -Milliseconds 50
            # Set-AzureADUserLicense -ObjectId $user.UPN -AddLicenses ...
            
            $licensed += [PSCustomObject]@{
                UPN = $user.UPN
                License = "E3"
                Status = "Licensed"
            }
            
            if ($licensed.Count % 50 -eq 0) {
                Write-Host "    Licensed $($licensed.Count) users..." -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Failed to license $($user.UPN): $_"
        }
    }
    
    Write-Host "  Successfully licensed: $($licensed.Count)" -ForegroundColor Gray
    Save-StepData $licensed "licensed-users"
}

New-Step {
    Write-Host "Step 5: Generating migration report..." -ForegroundColor Green
    
    $summary = Get-StepData "migration-summary"
    $validUsers = Get-StepData "valid-users"
    $invalidUsers = Get-StepData "invalid-users"
    $createdUsers = Get-StepData "azure-users-created"
    $failedUsers = Get-StepData "azure-users-failed"
    $licensedUsers = Get-StepData "licensed-users"
    
    $report = @"
User Migration Report
=====================
Start Time: $($summary.StartTime)
End Time: $(Get-Date)

Summary:
- Total Users Processed: $($summary.TotalUsers)
- Valid Users: $($validUsers.Count)
- Invalid Users: $($invalidUsers.Count)
- Created in Azure: $($createdUsers.Count)
- Failed Creation: $(if ($failedUsers) { $failedUsers.Count } else { 0 })
- Licensed: $($licensedUsers.Count)

Migration data saved to: .\data\
"@
    
    Write-Host ""
    Write-Host $report
    
    # Save report
    $report | Set-Content ".\data\migration-report.txt"
    
    Write-Host ""
    Write-Host "Migration completed successfully!" -ForegroundColor Green
}

Stop-Stepper

# Optionally clean up data files after successful completion
# Remove-Item "$dataDir\*.json" -Force
