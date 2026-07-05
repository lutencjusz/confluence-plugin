# Plugin `confluence`

[PL](README_PL.md) — full version in Polish.

Claude Code skills for [Confluence Cloud](https://lutencjusz.atlassian.net/wiki) via REST API v1: reading and searching (CQL), creating and editing pages (storage format), comments, attachments, and exporting a page to an Obsidian note.

## Skills
- **confluence-setup** — connection configuration and test (`~/.confluence/config.json`).
- **confluence-read** — read a page by ID/title, CQL search, list spaces, comments.
- **confluence-write** — create and update pages (content in storage format directly), add comments.
- **confluence-files** — upload and download page attachments.
- **confluence-export** — export a Confluence page to a Markdown note in the Obsidian vault (pandoc or fallback).

## Installation
```
/plugin marketplace add lutencjusz/confluence-plugin
/plugin install confluence@confluence-plugin
```

The skills import the shared PowerShell module (`lib/confluence.psm1`) via `$env:CLAUDE_PLUGIN_ROOT`, so the plugin works from any project regardless of where Claude Code installs it.

## Requirements
- Windows with PowerShell 7 (`pwsh`), `curl`.
- Confluence Cloud API token from https://id.atlassian.com/manage-profile/security/api-tokens
- Pester 5 only for running the test suite.
- Optional `pandoc` for storage → Markdown conversion on export.

## Configuration
Run the **confluence-setup** skill, which creates `~/.confluence/config.json` (`baseUrl`, `email`, `apiToken` — see [`config.example.json`](config.example.json)).

## ⚠️ Security
- The API token is passed to `curl` via stdin (`-K -`), never in process arguments.
- `config.json` is not committed (`.gitignore`); it lives outside the repo (`~/.confluence`).
- Skills never print `apiToken`; auth errors report only that the token/email is wrong.

## Tests
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"
```

See [README_PL.md](README_PL.md) for the full documentation (config field table, example prompts per skill).
