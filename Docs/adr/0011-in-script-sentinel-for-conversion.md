# ADR 0011: in-script sentinel variable for ConvertTo-StepperScript once-only guard

**Date:** 2026-05-03
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`ConvertTo-StepperScript` rewrites cross-step variable references inside `New-Step` blocks. It is invoked interactively during `New-Step`'s first-run hook (after `Repair-StepperScript`). The offer must be made at most once per script — re-prompting on every first run would be disruptive and confusing.

Three sentinel strategies were considered:

1. **State file key** — store `ConversionOffered = $true` in the Stepper state JSON. Cheap, no extra files. Disappears when the state is cleared (e.g. after `Stop-Stepper` on successful completion), so the offer reappears on the next full run.

2. **Sidecar file** — write a `.stepper-converted` marker file alongside the script. Survives all run cycles. Adds mystery files to the user's project; clutters source control.

3. **In-script sentinel variable** — inject `$StepperConversionComplete = $true` into the script itself after rewriting. The script is already modified by `ConvertTo-StepperScript`, so this is no additional mechanism. Survives all run cycles. No extra files. Visible and self-documenting. Deliberate revert requires deliberate removal of the sentinel, which is appropriate.

---

## Decision

`ConvertTo-StepperScript` injects the line `$StepperConversionComplete = $true` near the top of the script (after the install guard, before any `New-Step` blocks) as part of its rewrite pass. The first-run hook in `New-Step` checks for the presence of this variable before offering conversion.

---

## Rationale

- the script is already being modified, so one more injected line is zero extra complexity
- no sidecar files — the script itself is the authoritative record of conversion
- survives `Stop-Stepper`, state wipes, and re-clones without needing the state file
- self-documenting: anyone reading the script can see that conversion has already run
- if a user reverts the rewrite manually, removing the sentinel is an appropriate and obvious step

---

## Consequences

- `ConvertTo-StepperScript` gains responsibility for injecting `$StepperConversionComplete = $true` after rewriting
- `New-Step` first-run hook checks for the sentinel via AST scan (not `Test-Path Variable:StepperConversionComplete`) — the sentinel lives at script scope but `New-Step` is a function call; the variable is not in scope at the time of the check. `Get-ScriptAst` + `FindAll` for `VariableExpressionAst` named `StepperConversionComplete` is the correct approach, consistent with how `Find-CrossStepVariables` works
- scripts that were rewritten before this ADR will not have the sentinel; the first-run hook will offer conversion once more and then inject it
- `Find-CrossStepVariables` should treat `$Stepper.*` references as already-converted and exclude them from candidates
