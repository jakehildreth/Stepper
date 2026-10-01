![The Stepper logo features the word Stepper in a bold, stylized font with a set of stairs ascending diagonally to the right. The design conveys a sense of progress and upward movement, aligning with the tool's purpose of step-by-step automation. The background is plain, ensuring the logo remains the focal point. Font used: https://www.dafont.com/pix.font?fpp=200](Images/Stepper.png)

# Stepper

Ever write a PowerShell script that takes 45 minutes to run... and then watch it faceplant at minute 44? And then fix the bug, re-run it, and wait 44 minutes *again* just to find out if your fix worked?

Yeah. Me too. That's why Stepper exists.

Stepper is a cross-platform PowerShell module that makes your long-running scripts resumable. Wrap your code in `New-Step` blocks, and if something fails, the next run picks up at the step that failed instead of starting over from scratch. Completed steps are skipped. Your time is saved. Your sanity is preserved. Everyone wins.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/jakehildreth/Stepper)
[![PSGallery](https://img.shields.io/powershellgallery/v/Stepper)](https://www.powershellgallery.com/packages/Stepper)
![License](https://img.shields.io/badge/license-MIT%20w%2FCommons%20Clause-green)

---

## Quick Start

Install from the PowerShell Gallery:

```powershell
Install-Module -Name Stepper -Scope CurrentUser -Force
```

Scaffold a new script:

```powershell
New-StepperScript -Name 'MyScript'
```

Or write one by hand. It's just a `.ps1` with a `Start-Stepper` call up top and `New-Step` blocks below:

```powershell
[CmdletBinding()]   # required for -Verbose support and error propagation; auto-injected if missing
param()             # auto-injected if missing

#region Stepper ignore
if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }
Start-Stepper       # validates the script, initializes resume state and $Stepper
#endregion Stepper ignore

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

That `#region Stepper ignore` wrapper matters, by the way. It tells Stepper's unmanaged-code detection to leave the bootstrap alone. The guard inside it installs Stepper from the Gallery if you don't already have it, so the script just works on a fresh machine.

"But Jake," you ask, "what's `Start-Stepper` doing up there?"

Everything, and I mean *everything*, before your code runs. It validates the whole script structure, checks that lifecycle calls are where they belong, finds any loose code living outside your steps, and walks you through fixing what it finds. If it has to rewrite your source (adding a missing `[CmdletBinding()]` or `Start-Stepper`, for example), it makes a backup first, clears stale state, and exits with code `75`. Run the script again and you're off. Dot-sourcing is a no-go, by the way... Stepper needs to be able to stop safely after a rewrite.

Running unattended? In non-interactive hosts, the safe deterministic fixes happen automatically. Anything that needs your judgment fails safe instead of guessing.

Stepper also logs every step's execution timing, host output, and a per-step transcript to `<scriptname>.ps1.stepper.log` by default. No configuration required. It Just Works™.

---

## See It In Action

https://github.com/user-attachments/assets/4717179e-1698-4e19-aac3-e514d04333b8

Created with [VHS](https://github.com/charmbracelet/vhs) by [Charm](https://charm.land). Fancy terminal recording, zero effort on my part. The best kind.

---

## Digging Deeper

If you want the full story, the docs have you covered:

- [How It Works](Docs/how-it-works.md): execution lifecycle, resume logic, verbose output, non-interactive mode
- [Named Steps](Docs/named-steps.md): step names, `$Stepper.StepName`, resume prompt formats
- [Data Persistence](Docs/data-persistence.md): `$Stepper` hashtable, state file schema
- [Logging](Docs/logging.md): log files, step transcripts, `-LogPath`, `-NoLog`
- [Unmanaged Code](Docs/unmanaged-code.md): detection, `#region Stepper ignore`, interactive resolution
- [API Reference](Docs/api-reference.md): `Start-Stepper`, `New-Step`, `Stop-Stepper`, `New-StepperScript`, `Test-StepperScript`, `Repair-StepperScript`, `ConvertTo-StepperScript`
- [Examples](Docs/examples.md)
- [Troubleshooting](Docs/troubleshooting.md)

---

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
