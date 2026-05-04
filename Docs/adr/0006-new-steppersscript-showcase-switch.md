# ADR 0006: New-StepperScript template verbosity controlled by -Showcase switch

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`New-StepperScript` generates a new `.ps1` file pre-wired for Stepper. The question was how much content to include by default.

Two extremes:
1. **Minimal skeleton**: just the structural requirements: CBH, `[CmdletBinding()] param()`, install guard, two placeholder `New-Step` blocks, `Stop-Stepper`. Minimal noise, immediately editable.
2. **Feature-showcase template**: everything in minimal, plus commented examples demonstrating named steps, `$Stepper.<var>` persistence, `-NoLog`, `-Retry`/`-RetryInterval`/`-MaxRetries`, and `#region Stepper ignore` blocks.

Both templates can be useful in either situation; the right choice depends on intent, not experience level. A single fixed template forces a tradeoff: a minimal-only tool requires users to look up API details elsewhere; a showcase-only tool clutters files that just need a starting point.

The solution is a default of minimal with an opt-in flag for the full showcase.

---

## Decision

`New-StepperScript` produces a minimal skeleton by default. The `-Showcase` switch (with aliases `-Full`, `-Detailed`, `-WithExamples`) produces the full feature-demo template.

---

## Rationale

- Minimal is the right default because the common case is starting a new script, not exploring the API; less to delete, immediately writable
- Showcase is the right opt-in for any time you want in-file examples as a reference, regardless of experience level
- Aliases make the flag discoverable; users who think `-Full` or `-WithExamples` are likely to get tab-completion
- Single implementation path per template variant (no runtime branching inside each `New-Step` block)

---

## Consequences

```powershell
[Alias('Full', 'Detailed', 'WithExamples')]
[switch]$Showcase
```

- Minimal template: CBH + `[CmdletBinding()] param()` + install guard + 2 placeholder `New-Step {}` blocks + `Stop-Stepper`
- Showcase template: all of the above + commented examples of `$Stepper.<var>`, named steps, `-NoLog`, `-Retry`, `#region Stepper ignore`
- Both templates pass `Test-StepperScript` with `IsValid = $true` out of the box
