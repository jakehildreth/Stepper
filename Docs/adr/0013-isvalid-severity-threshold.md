# ADR 0013: IsValid reflects Error-severity issues only

**Date:** 2026-05-30
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`Test-StepperScript` returns a `PSCustomObject` with an `IsValid` boolean and an `Issues` array. Issues have two severity levels:

- `Error` — `MissingCmdletBinding`, `MissingInstallGuard`
- `Warning` — `MissingCbh`, `MissingStopStepper`, `NoSteps`

The question arose: should `IsValid` be `$false` when `Stop-Stepper` is missing?

---

## Decision

`IsValid = $true` when no `Error`-severity issues are present. `Warning`-severity issues do not affect `IsValid`.

---

## Rationale

- a missing `Stop-Stepper` will not cause Stepper to fail or behave incorrectly at runtime — it only means the state file is not cleaned up after a successful run, which is recoverable and cosmetic
- `MissingCmdletBinding` and `MissingInstallGuard` are true blockers: without them the script cannot use `-WhatIf`/common parameters and will not self-install Stepper on a clean machine
- `IsValid` is used by `New-Step` at first-run to decide whether `Repair-StepperScript` needs to run; including warnings in that gate would trigger unnecessary repairs on valid scripts
- consumers who want stricter validation can inspect `Issues` directly and filter by `Severity`
