# Stepper PowerShell Module

A modular PowerShell framework for building resumable multi-step steppers with state persistence.

## Features

- ✅ **State Persistence** - Automatically saves progress after each step
- ✅ **Resume Capability** - Pick up where you left off if interrupted
- ✅ **Modular Design** - Easy to customize and extend
- ✅ **Error Handling** - Graceful failure recovery
- ✅ **Progress Tracking** - Visual feedback and completion percentage
- ✅ **PowerShell Best Practices** - Follows approved verb naming and structure

## Quick Reference

| What You Want | Command |
|--------------|---------|
| Run your stepper (resumes automatically) | `Start-Stepper` |
| Start fresh, ignore saved progress | `Start-Stepper -Fresh` |
| Check current progress | `Show-StepperStatus` |
| List available steps | `Get-StepperSteps` |
| Reset all progress | `Reset-StepperState` |

> **Tip:** The module auto-discovers JSON config files! If your script is `My-Script.ps1`, create `My-Script.json` in the same directory.

## Installation

### From PowerShell Gallery (Coming Soon)
```powershell
# Install for current user
Install-Module -Name Stepper -Scope CurrentUser

# Import the module
Import-Module Stepper
```

### Manual Installation
```powershell
# Clone or download the repository
git clone https://github.com/jakehildreth/Stepper.git

# Change to Stepper directory
Set-Location .\Stepper

# Import the module
Import-Module .\Stepper.psd1 -Force
```

## Usage

### Basic Workflow

```powershell
# First run - starts a new stepper
Start-Stepper

# If interrupted, just run again - automatically resumes!
Start-Stepper

# Want to start over? Use -Fresh
Start-Stepper -Fresh

# Check what's completed without running anything
Show-StepperStatus

# See what steps are configured
Get-StepperSteps

# Clear all progress and start fresh
Reset-StepperState
```

### Using with Your Own Scripts

The Stepper module automatically discovers JSON configuration files:

```powershell
# If your script is named: My-HealthCheck.ps1
# Create a config file: My-HealthCheck.json (in same directory)
# Stepper automatically finds it!

Import-Module Stepper
Start-Stepper  # Auto-discovers My-HealthCheck.json
```

### Example Session

```powershell
PS> Import-Module Stepper
PS> Start-Stepper

══════════════════════════════════════════════════════════════════
 Multi-Step stepper Tool
 Version 1.0.0
══════════════════════════════════════════════════════════════════

Loaded 4 health check step(s)

──────────────────────────────────────────────────────────────────
Step 1 of 4: SystemInfo
──────────────────────────────────────────────────────────────────
  Collect system information

  ✓ Step completed successfully in 1.23s

  Press Enter to continue to the next step, or Ctrl+C to stop...
```

## Customization

### Quick Example: Adding a Custom Step

The module uses JSON configuration with individual step script files:

**1. Create a step script** (e.g., `Steps/Step-MyCheck.ps1`):
```powershell
<#
.SYNOPSIS
    My custom health check.
#>

Write-Host "  Running my custom check..." -ForegroundColor Yellow

# Your check logic here
$result = @{
    Status = "Success"
    Details = "All systems operational"
}

Write-Host "  ✓ Check completed" -ForegroundColor Green
return $result
```

**2. Add to your JSON config** (e.g., `my-script.json`):
```json
{
  "stepperSteps": [
    {
      "name": "MyCheck",
      "description": "My custom health check",
      "scriptPath": "Steps/Step-MyCheck.ps1",
      "enabled": true,
      "order": 1,
      "acceptsAllResults": false
    }
  ]
}
```

**3. Run it:**
```powershell
Import-Module Stepper
Start-Stepper  # Auto-discovers my-script.json
```

### Configuration Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | string | Unique identifier for state tracking |
| `description` | string | Shown to users during execution |
| `scriptPath` | string | Path to step script (relative to JSON file) |
| `enabled` | boolean | `true` to run, `false` to skip |
| `order` | number | Execution order (ascending) |
| `acceptsAllResults` | boolean | `true` if step needs previous results |

### Accessing Previous Step Results

If your step needs data from previous steps:

```powershell
# Set acceptsAllResults: true in JSON config
# Add param block to your step script

param($AllResults)

$previousStep = $AllResults['PreviousStepName']
Write-Host "Previous result: $($previousStep.Status)"

return @{ MyResult = "Success" }
```

### Complete Working Example

For a full example with 4 steps, see the **Windows Health Check** in the `Examples/` directory:

```powershell
cd Examples\Windows Health Check
.\Invoke-WindowsHealthCheck.ps1
```

See [Examples/Windows Health Check/README.md](Examples/Windows%20Health%20Check/README.md) for detailed documentation.

## State Management

### State File Location
State is saved to: `$env:USERPROFILE\.stepper\stepper-state.json`

### State Structure
```json
{
  "Version": "1.0.0",
  "StepperId": "guid",
  "StartedAt": "ISO8601 timestamp",
  "LastUpdated": "ISO8601 timestamp",
  "CompletedSteps": ["Step1", "Step2"],
  "CurrentStepIndex": 2,
  "Status": "InProgress|Completed|Failed",
  "StepResults": {
    "Step1": {
      "Status": "Completed",
      "CompletedAt": "timestamp",
      "Duration": "1.23s",
      "Result": { }
    }
  },
  "Metadata": {
    "ComputerName": "HOSTNAME",
    "UserName": "username",
    "PSVersion": "5.1"
  }
}
```

### State Validation
- State files older than 7 days trigger a warning
- Version mismatches trigger a warning
- Invalid timestamps are detected

## Functions

### Public Functions

#### `Start-Stepper`
Main function to run the stepper with automatic resume.

```powershell
# Run stepper (resumes automatically if state exists)
Start-Stepper

# Start fresh, ignoring saved state
Start-Stepper -Fresh
```

#### `Show-StepperStatus`
Display current progress without running any steps.

```powershell
Show-StepperStatus
```

#### `Get-StepperSteps`
Load and display configured steps from JSON.

```powershell
# Auto-discover config based on calling script
Get-StepperSteps

# Use specific config file
Get-StepperSteps -ConfigPath ".\my-config.json"
```

#### `Reset-StepperState`
Clear all saved state and start fresh.

```powershell
# With confirmation prompt
Reset-StepperState

# Skip confirmation
Reset-StepperState -Confirm:$false

# Preview what will be deleted
Reset-StepperState -WhatIf
```

For detailed help on any function:
```powershell
Get-Help Start-Stepper -Full
Get-Help Get-StepperSteps -Examples
```

## Examples

### Complete Working Example: Windows Health Check

See the `Examples/Windows Health Check/` directory for a complete implementation with 4 steps:

```powershell
# Navigate to example
cd Examples\Windows Health Check

# Run the health check
.\Invoke-WindowsHealthCheck.ps1

# Or start fresh
.\Invoke-WindowsHealthCheck.ps1 -Fresh
```

This example demonstrates:
- ✅ Auto-discovery of JSON configuration
- ✅ Individual step files with proper documentation
- ✅ Data sharing between steps
- ✅ Professional output with color-coding
- ✅ Comprehensive final summary report

See [Examples/Windows Health Check/README.md](Examples/Windows%20Health%20Check/README.md) for detailed documentation.

## Best Practices

1. **Keep Steps Atomic** - Each step should do one logical task
2. **Return Structured Data** - Return hashtables/objects, not just text
3. **Add Verbose Output** - Use `Write-Verbose` for debugging
4. **Handle Errors Gracefully** - Use try/catch in your step scripts
5. **Test Incrementally** - Test each step individually before running the full stepper
6. **Save Important Data** - Return data you might need in later steps or reports
7. **Use Auto-Discovery** - Name your JSON config to match your script filename

## Troubleshooting

### Module Not Loading
```powershell
# Check if module is available
Get-Module -ListAvailable -Name Stepper

# Import with verbose output
Import-Module Stepper -Verbose -Force
```

### State File Issues
```powershell
# View current state
Get-Content "$env:USERPROFILE\.stepper\stepper-state.json" | ConvertFrom-Json | ConvertTo-Json -Depth 10

# Reset corrupted state
Reset-StepperState -Confirm:$false
```

### Step Not Running
```powershell
# Check if step is enabled in JSON config
Get-StepperSteps | Format-Table Name, Description

# Test step script directly
.\Steps\Step-YourStepName.ps1
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This module is provided as-is under the MIT License.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.
