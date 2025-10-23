# Stepper - Changelog# Stepper - Changelog



All notable changes to the Stepper module will be documented in this file.## Version 1.0.0 - October 23, 2025



## [1.0.0] - 2025-10-23### Major Refactoring: JSON Configuration with Separate Step Files



### Added**Breaking Change:** Steps are now defined in JSON configuration with individual script files instead of hardcoded scriptblocks.

- Initial release of Stepper module

- JSON-based step configuration with external script files#### What Changed

- State persistence with automatic resume capability

- 4 public functions: `Start-Stepper`, `Show-StepperStatus`, `Get-StepperSteps`, `Reset-StepperState`1. **New Files Created:**

- 10 private helper functions for state management   - `stepper-config.json` - Step configuration file

- Complete Windows Health Check example with 4 steps   - `Steps/` directory with 6 individual step script files

- Auto-discovery: automatically finds JSON config matching script filename   - `REFACTORING-SUMMARY.md` - Detailed refactoring documentation

- PowerShell 5.1+ compatibility

2. **Modified Files:**

### Features   - `Private/Get-StepperSteps.ps1` - Now loads steps from JSON

- **State Management**: Automatic save/resume after each step   - `Private/Invoke-StepperStep.ps1` - Uses `AcceptsAllResults` property

- **JSON Configuration**: Define steps in external JSON files   - `README.md` - Updated customization section

- **Step Scripts**: Individual .ps1 files for each step with full documentation   - `QUICK-REFERENCE.md` - Updated with new JSON approach

- **Auto-Discovery**: Script.ps1 automatically finds Script.json in same directory

- **Professional Output**: Color-coded, progress indicators, Unicode symbols3. **Step Files Added:**

- **Enable/Disable Steps**: Toggle steps via JSON without deleting code   - `Steps/Step-EnvironmentCheck.ps1`

- **Data Sharing**: Steps can access results from previous steps via `$AllResults`   - `Steps/Step-SystemInventory.ps1`

   - `Steps/Step-NetworkConfiguration.ps1`

### Default Behavior   - `Steps/Step-SecurityBaseline.ps1`

- `Start-Stepper` resumes from last checkpoint by default (no switch needed)   - `Steps/Step-ServiceCheck.ps1`

- Use `Start-Stepper -Fresh` to start over, ignoring saved state   - `Steps/Step-GenerateReport.ps1`



---#### Benefits



**Note:** This module follows [Semantic Versioning](https://semver.org/).✅ **Easier Configuration** - Edit JSON instead of PowerShell code  

✅ **Better Organization** - Each step is its own documented file  
✅ **Enable/Disable Steps** - Toggle with `"enabled": true/false`  
✅ **More Testable** - Test individual step scripts independently  
✅ **Better Version Control** - Clearer diffs when steps change  
✅ **Non-Technical Friendly** - JSON easier for non-programmers  

#### Migration Required

If you customized the old `Get-StepperSteps.ps1`:

1. Create individual `.ps1` files in `Steps/` directory for each step
2. Add step definitions to `stepper-config.json`
3. Set `"acceptsAllResults": true` for steps that need previous results

See `REFACTORING-SUMMARY.md` for complete migration guide.

---

### Start-Stepper Default Behavior Change

**Breaking Change:** The default behavior has been reversed for better UX.

#### Before ❌
```powershell
Start-Stepper          # Started fresh (ignored saved state)
Start-Stepper -Resume  # Resumed from checkpoint
```

#### After ✅
```powershell
Start-Stepper          # Resumes from checkpoint (DEFAULT)
Start-Stepper -Fresh   # Starts fresh (ignores saved state)
```

#### Rationale

Resume is the common case (90% of usage). Users shouldn't need a switch for the default action.

#### Migration

Replace:
```powershell
Start-Stepper -Resume  # Old way
```

With:
```powershell
Start-Stepper  # New way (resume is default)
```

For starting fresh:
```powershell
Start-Stepper -Fresh  # New explicit switch
```

---

## Version History

### v1.0.0 - October 23, 2025
- ✅ Initial modular release
- ✅ JSON-based configuration
- ✅ Separate step script files
- ✅ State persistence with resume capability
- ✅ Default resume behavior
- ✅ Comprehensive documentation
- ✅ 3 public functions (Start-Stepper, Show-StepperStatus, Reset-StepperState)
- ✅ 11 private helper functions
- ✅ 6 example stepper steps

---

## Quick Reference

| What You Want | Command |
|--------------|---------|
| Continue from where I stopped | `Start-Stepper` |
| See what's already done | `Show-StepperStatus` |
| Start over completely | `Start-Stepper -Fresh` |
| Clear everything | `Reset-StepperState` |
| Add new step | Create script in `Steps/`, add to `stepper-config.json` |
| Disable step | Set `"enabled": false` in `stepper-config.json` |

---

**Module Name:** Stepper  
**Current Version:** 1.0.0  
**PowerShell:** 5.1+  
**Tested On:** PowerShell 7.5.3, Windows Server 2022

## What Changed

The default behavior of `Start-Stepper` has been **reversed** for better user experience.

### Before ❌
```powershell
Start-Stepper          # Started fresh (ignored saved state)
Start-Stepper -Resume  # Resumed from checkpoint
```

### After ✅
```powershell
Start-Stepper          # Resumes from checkpoint (DEFAULT)
Start-Stepper -Fresh   # Starts fresh (ignores saved state)
```

## Rationale

**Smart defaults:** Most users want to resume where they left off, not restart from scratch. This change makes the common case (resuming) the default behavior.

## Usage Examples

### Resume from Last Checkpoint (Default)
```powershell
# Just run it - will pick up where you left off
Start-Stepper
```

**Output:**
```
Resuming from saved state...

Progress Summary:
  --------------------------------------------------
  stepper ID    : a1b2c3d4-...
  Started At       : 2025-10-23T10:30:00
  Last Updated     : 2025-10-23T10:35:15
  Status           : InProgress
  Completed Steps  : 3 / 6 (50.0%)
  --------------------------------------------------

Completed Steps:
  ✓ EnvironmentCheck (1.23s)
  ✓ SystemInventory (2.45s)
  ✓ NetworkConfiguration (3.12s)
```

### Start Completely Fresh
```powershell
# Use -Fresh to ignore saved state and start over
Start-Stepper -Fresh
```

**Output:**
```
Starting fresh stepper (ignoring saved state)...

Progress Summary:
  --------------------------------------------------
  stepper ID    : new-guid-...
  Started At       : 2025-10-23T11:00:00
  Last Updated     : 2025-10-23T11:00:00
  Status           : InProgress
  Completed Steps  : 0 / 6 (0.0%)
  --------------------------------------------------
```

### Check Progress First
```powershell
# See what's already done before resuming
Show-StepperStatus

# Then resume
Start-Stepper
```

## Migration Guide

If you have scripts that use the old syntax:

### Old Script
```powershell
# Old way - explicitly resume
Start-Stepper -Resume
```

### Updated Script
```powershell
# New way - just run it (resume is default)
Start-Stepper

# Or be explicit if you prefer
Start-Stepper  # This now resumes by default
```

### Starting Fresh
```powershell
# Old way
# (no equivalent - had to clear state manually)

# New way
Start-Stepper -Fresh
```

## Benefits

1. **Better UX** - Resume is what users want 90% of the time
2. **Fewer commands** - No need to remember `-Resume` switch
3. **Safer** - Less likely to accidentally restart a long stepper
4. **Explicit override** - Use `-Fresh` when you really want to start over
5. **Consistent** - Matches common patterns (git, browser tabs, etc.)

## State File Behavior

The state file location hasn't changed:
- **Location:** `$env:USERPROFILE\.stepper\stepper-state.json`
- **Auto-created:** If no state exists, creates new one
- **Auto-saved:** After each step completes
- **Validated:** Checks age/version before resuming

### When Starting Fresh is Better

Use `Start-Stepper -Fresh` when:
- Previous stepper was from different environment
- You want to collect fresh data
- State file is corrupted or outdated
- Testing after making changes to stepper steps

### When Resuming is Better (Default)

Just run `Start-Stepper` when:
- You were interrupted mid-stepper
- You want to skip already-completed steps
- You're continuing from where you left off
- You want to re-run only specific steps

## Complete Workflow Example

```powershell
# Day 1: Start stepper
PS> Import-Module Stepper
PS> Start-Stepper

# ... runs steps 1-3, then you stop for the day ...

# Day 2: Continue where you left off
PS> Import-Module Stepper
PS> Show-StepperStatus  # Optional: see what's done
PS> Start-Stepper       # Resumes automatically!

# ... completes steps 4-6 ...

# Day 3: Run fresh stepper for different system
PS> Import-Module Stepper
PS> Start-Stepper -Fresh  # Explicitly start fresh
```

## Quick Reference

| What You Want | Command |
|--------------|---------|
| Continue from where I stopped | `Start-Stepper` |
| See what's already done | `Show-StepperStatus` |
| Start over completely | `Start-Stepper -Fresh` |
| Clear everything and start | `Reset-StepperState` then `Start-Stepper` |

---

**Updated:** October 23, 2025  
**Module Version:** 1.0.0  
**Backward Compatibility:** ⚠️ Breaking change - `-Resume` parameter removed, replaced with default behavior
