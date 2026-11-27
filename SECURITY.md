# Security Policy

## Supported versions

Security fixes are prioritized for the latest published Stepper release and
the current `main` branch. If you are using an older release, upgrade to the
latest release before reporting unless the issue is specific to the upgrade
path.

## Reporting a vulnerability

Do not report security vulnerabilities in public GitHub issues, discussions, or
pull requests.

Email vulnerability reports to <security@gilmour.ltd>. Include as much of the
following information as you can safely share:

- The Stepper version or commit SHA.
- The affected command, function, or step-execution path.
- The operating system and PowerShell versions used.
- A clear description of the security impact.
- Minimal reproduction steps, sample output, or logs with secrets and sensitive
  environment details removed.
- Whether the issue is already being exploited or publicly discussed.

The maintainers will review the report, coordinate follow-up privately, and
publish public details after a fix or mitigation is available when disclosure is
appropriate.

## Handling sensitive script data

Stepper executes PowerShell scripts step by step and can write state files,
logs, and backups to disk. These files can contain script content, paths, and
command output. Remove organization-specific or sensitive values before sharing
scripts, state files, logs, backups, or command output publicly.
