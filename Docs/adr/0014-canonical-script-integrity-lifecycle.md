# ADR 0014: Canonical Stepper script integrity lifecycle

**Status:** Accepted

A Stepper script is validated through one AST-derived finding catalog before runtime state is created or read. `Test-StepperScript` is the sole source of findings, deterministic additions use one shared private repair implementation, and `Start-Stepper` owns ordered interactive remediation; no caller performs a separate integrity check.

The pipeline is parse → deterministic additions → blocking structural Errors → lifecycle-call remediation → unmanaged-code remediation → deferred `NoSteps` enforcement → missing Stop decision → cross-step conversion → runtime state. Every rewrite creates one backup, writes once, removes stale state, and stops with exit code 75 so the next run uses fresh source locations, script hash, and step inventory.

Warnings never receive automatic repair. Stepper does not evaluate script quality, so comment-based help is not a finding. Missing Stop remains an interactive Warning. Non-interactive runs use explicit outcomes and never wait for input or silently move lifecycle calls or convert variables. The accepted `-SkipRequirementsCheck` parameter remains as an undocumented compatibility no-op; the complete integrity pipeline always runs.

This decision supersedes ADRs 0003, 0005, 0008, and 0011. ADR 0009 remains authoritative for public command names, ADR 0012 remains authoritative for centralized backups, and ADR 0013 remains authoritative for `IsValid` being false only when Error findings exist.
