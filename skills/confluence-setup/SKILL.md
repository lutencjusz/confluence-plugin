---
name: confluence-setup
description: Use when configuring the Confluence Cloud connection or testing it — creating ~/.confluence/config.json (baseUrl, email, API token) and verifying that the REST API works. Triggers: "skonfiguruj Confluence", "połącz z Confluence", "sprawdź połączenie z Confluence", "test confluence".
---

# confluence-setup

Konfiguruje połączenie z Confluence Cloud i testuje je.

## Konfiguracja docelowa

Plik `~/.confluence/config.json` (poza repo; na Windows `%USERPROFILE%\.confluence\config.json`):

| Pole | Znaczenie | Źródło |
|------|-----------|--------|
| `baseUrl` | bazowy URL wiki (bez końcowego `/`) | np. `https://lutencjusz.atlassian.net/wiki` |
| `email` | e-mail konta Atlassian | konto |
| `apiToken` | token API | https://id.atlassian.com/manage-profile/security/api-tokens |

## Procedura

1. Zapytaj użytkownika o: `baseUrl`, `email`, token API.
2. Zaimportuj moduł i zapisz konfigurację:
   ```powershell
   Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/confluence.psm1" -Force
   $dir = Join-Path $HOME '.confluence'
   if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
   @{
     baseUrl='https://lutencjusz.atlassian.net/wiki'
     email='WKLEJ_EMAIL'; apiToken='WKLEJ_TOKEN'
   } | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'config.json') -Encoding utf8
   ```
3. Test połączenia:
   ```powershell
   $cfg = Get-ConfluenceConfig
   "Spaces:"; (Get-ConfluenceSpaces -Limit 1 -Config $cfg).results.key
   ```
4. Raportuj wynik: czy API odpowiada; przy błędzie 401/403 — zły token/e-mail.

## Uwagi
- Nigdy nie wypisuj `apiToken` w odpowiedzi ani nie commituj `config.json`.
- Token generujesz na https://id.atlassian.com/manage-profile/security/api-tokens.
