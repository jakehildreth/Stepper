![The Stepper logo features the word Stepper in a bold, stylized font with a set of stairs ascending diagonally to the right. The design conveys a sense of progress and upward movement, aligning with the tool's purpose of step-by-step automation. The background is plain, ensuring the logo remains the focal point. Font used: https://www.dafont.com/pix.font?fpp=200](Images/Stepper.png)

# Stepper

A cross-platform PowerShell utility module for creating resumable, step-by-step scripts with automatic state persistence.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
[![PSGallery](https://img.shields.io/powershellgallery/v/Stepper)](https://www.powershellgallery.com/packages/Stepper)
![License](https://img.shields.io/badge/license-MIT%20w%2FCommons%20Clause-green)

---

## Quick Start

```powershell
Install-Module -Name Stepper -Scope CurrentUser -Force
```

Scaffold a new script (or create one manually):

```powershell
New-StepperScript -Name 'MyScript'
```

Or create a `.ps1` script with `New-Step` blocks by hand:

```powershell
[CmdletBinding()]   # required for -Verbose support and error propagation; auto-injected if missing
param()             # auto-injected if missing

New-Step 'Download Files' {
    Write-Host "Downloading files..."
    # your code here
}

New-Step 'Process Data' {
    Write-Host "Processing data..."
    # your code here
}

New-Step 'Upload Results' {
    Write-Host "Uploading results..."
    # your code here
}

Stop-Stepper   # removes the state file on successful completion
```

If the script fails inside a `New-Step` block, the next run resumes at the step that failed. All previously completed steps are skipped!

On first run, Stepper checks for `[CmdletBinding()]` and the self-install guard independently. Each component is silently injected if missing (the guard is wrapped in `#region Stepper ignore` so it won't trigger unmanaged-code warnings), then Stepper exits and asks you to re-run. Nothing is required beyond what's shown above.

Stepper also logs every step's execution timing, host output, and a per-step transcript to `<scriptname>.ps1.stepper.log` by default. No configuration required.

---

## Demo

https://github.com/user-attachments/assets/4717179e-1698-4e19-aac3-e514d04333b8

Created with [VHS](https://github.com/charmbracelet/vhs) by [Charm](https://charm.land).

---

## Learn More

- [How It Works](Docs/how-it-works.md): execution lifecycle, resume logic, verbose output, non-interactive mode
- [Named Steps](Docs/named-steps.md): step names, `$Stepper.StepName`, resume prompt formats
- [Data Persistence](Docs/data-persistence.md): `$Stepper` hashtable, state file schema
- [Logging](Docs/logging.md): log files, step transcripts, `-LogPath`, `-NoLog`
- [Unmanaged Code](Docs/unmanaged-code.md): detection, `#region Stepper ignore`, interactive resolution
- [API Reference](Docs/api-reference.md): `New-Step`, `Stop-Stepper`, `New-StepperScript`, `Test-StepperScript`, `Repair-StepperScript`, `ConvertTo-StepperScript`
- [Examples](Docs/examples.md)
- [Troubleshooting](Docs/troubleshooting.md)

---

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
