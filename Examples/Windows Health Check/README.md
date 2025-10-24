# Windows Computer Health Check Example

This example demonstrates how to use the Stepper module to create a resumable multi-step script.

## What This Example Does

The Windows Health Check script performs a comprehensive system health check with the following steps:

1. **System Information** - Collects OS details, uptime, and hardware info
2. **Disk Space Analysis** - Checks free space on all drives and warns if low
3. **Windows Update Status** - Verifies update service and checks for pending updates
4. **Critical Services** - Ensures essential Windows services are running

## Files Included

```
Windows Health Check/
├── Invoke-WindowsHealthCheck.ps1           # Main script
├── Invoke-WindowsHealthCheck.json          # Step configuration
├── Steps/
│   ├── Step-SystemInfo.ps1                # Step 1: System info
│   ├── Step-DiskSpace.ps1                 # Step 2: Disk analysis
│   ├── Step-WindowsUpdate.ps1             # Step 3: Update status
│   └── Step-CriticalServices.ps1          # Step 4: Service check
└── README.md                               # This file
```

## How to Run

### Basic Usage

```powershell
# Run the health check (resumes if interrupted)
.\Invoke-WindowsHealthCheck.ps1

# Start fresh, ignoring any saved progress
.\Invoke-WindowsHealthCheck.ps1 -Fresh

# Check current progress
.\Invoke-WindowsHealthCheck.ps1 -ShowStatus

# Reset all progress
.\Invoke-WindowsHealthCheck.ps1 -Reset
```

### Expected Output

```
╔════════════════════════════════════════════════════╗
║                                                    ║
║     Windows Computer Health Check Tool            ║
║                                                    ║
╚════════════════════════════════════════════════════╝

Computer: DESKTOP-ABC123
User: Administrator
Date: 2025-10-23 14:30:00

Loaded 4 health check step(s)

--- System Information ---
Operating System:
  Name          : Microsoft Windows 11 Pro
  Version       : 10.0.22621
  ...

--- Disk Space Analysis ---
...

--- Windows Update Status ---
...

--- Critical Services Check ---
...

============================================================
HEALTH CHECK COMPLETE - SUMMARY REPORT
============================================================

Overall Status: HEALTHY ✓
```

## Key Features Demonstrated

### 1. State Persistence
The script automatically saves progress after each step. If interrupted (Ctrl+C), simply run it again to resume.

### 2. Individual Step Files
Each health check step is in its own file, making it easy to:
- Add new checks
- Modify existing checks
- Disable checks via the JSON config
- Test steps individually

### 3. Configuration-Driven
Steps are defined in `Invoke-WindowsHealthCheck.json`:

```json
{
  "StepperSteps": [
    {
      "name": "SystemInfo",
      "description": "Collect system information",
      "scriptPath": "Steps/Step-SystemInfo.ps1",
      "enabled": true,
      "order": 1
    }
  ]
}
```

### 4. Data Sharing Between Steps
Steps can share data using `$global:HealthCheckResults`. The final step (Step 4) uses this to generate a comprehensive summary.

### 5. Professional Output
Uses color-coding and Unicode symbols (✓, ❌, ⚠️) for clear visual feedback.

## Customizing for Your Needs

### Adding a New Step

1. Create a new script file in `Steps/`:
```powershell
# Step-MyCustomCheck.ps1
param()

Write-Host "Running my custom check..." -ForegroundColor Yellow
# Your check logic here
return $true  # or $false if check fails
```

2. Add to `Invoke-WindowsHealthCheck.json`:
```json
{
  "name": "MyCustomCheck",
  "description": "My custom health check",
  "scriptPath": "Steps/Step-MyCustomCheck.ps1",
  "enabled": true,
  "order": 5
}
```

### Disabling a Step

Set `"enabled": false` in the JSON config:
```json
{
  "name": "WindowsUpdate",
  "enabled": false,  // This step will be skipped
  ...
}
```

### Changing Step Order

Modify the `"order"` value in the JSON config. Steps execute in ascending order.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Stepper module installed
- Some checks may require administrator privileges

## Best Practices Shown

1. ✅ **Clear parameter documentation** - Comprehensive help text
2. ✅ **Error handling** - Try/catch blocks with meaningful messages
3. ✅ **Visual feedback** - Color-coded output and progress indicators
4. ✅ **Return values** - Each step returns $true/$false for success/failure
5. ✅ **Data persistence** - Results stored in $global variable for summary
6. ✅ **Resumable execution** - Leverages Stepper's state management
7. ✅ **Clean separation** - Each step is independent and testable

## Adapting to Other Use Cases

This pattern works great for:
- **Deployment scripts** - Multi-step application deployments
- **Migration scripts** - Moving data or configurations
- **Security assessments** - Checking multiple security settings
- **Maintenance tasks** - System cleanup and optimization
- **Setup wizards** - Complex installation procedures
- **Backup operations** - Multi-stage backup processes

Simply:
1. Copy the script structure
2. Create your own step files
3. Update the JSON configuration
4. Customize the main script header/output

## Troubleshooting

### Script won't resume
```powershell
# Check status
.\Invoke-WindowsHealthCheck.ps1 -ShowStatus

# If corrupted, reset
.\Invoke-WindowsHealthCheck.ps1 -Reset
```

### Step fails repeatedly
Edit the JSON config to disable the problematic step temporarily:
```json
"enabled": false
```

### Want to see step definitions
```powershell
# In PowerShell
Import-Module Stepper
Get-StepperSteps -ConfigPath ".\Invoke-WindowsHealthCheck.json"
```

## Learn More

- [Stepper Module Documentation](../README.md)
- [PowerShell Best Practices](https://docs.microsoft.com/powershell)

## License

This example is part of the Stepper module and follows the same license.
