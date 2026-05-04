# ADR 0004: Convert-StepperScript supports both in-place and -OutputPath rewrites

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`Convert-StepperScript` rewrites variable references inside `New-Step` blocks from `$var` to `$Stepper.Var`. A rewrite tool that modifies files needs a clear answer to "where does the output go?"

Two options were considered:
1. **In-place only**: always overwrites the source file
2. **In-place with backup + optional -OutputPath**: default is in-place with a `.bak` copy; `-OutputPath` writes to a new file instead, leaving the original untouched

Option 1 is simpler but gives users no recovery path if the rewrite produces unexpected results. A `.bak` is trivial to create and provides a safety net without any extra cognitive overhead.

Option 2 gives maximum flexibility: users who want a diff-friendly workflow can write to a new path and review before replacing the original. Users who want quick in-place rewrites get that as the default.

---

## Decision

`Convert-StepperScript` defaults to in-place modification + a `.bak` backup of the original. If `-OutputPath` is provided, the rewritten content is written to that path instead and the source file is not touched.

---

## Rationale

- In-place is the expected UX for a "migration" tool (lower friction)
- `.bak` is zero-cost insurance; most users will never need it, but they'll be grateful when they do
- `-OutputPath` enables review workflows and CI dry-run scenarios without a separate `-WhatIf` level of complexity
- Consistent with how other script-rewriting tools in the ecosystem behave (e.g. `2to3`, `ps-upgrade`)

---

## Consequences

- `Convert-StepperScript` has a common `-OutputPath [string]` optional parameter
- When `-OutputPath` is absent: reads source, writes `.bak`, writes rewritten content back to source
- When `-OutputPath` is present: reads source, writes rewritten content to `-OutputPath`, source untouched, no `.bak`
- `-WhatIf` support via `SupportsShouldProcess`; prints what would change without writing anything
