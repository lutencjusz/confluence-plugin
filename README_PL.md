# Plugin `confluence`

[EN](README.md)

Skille Claude Code do obsługi [Confluence Cloud](https://www.atlassian.com/software/confluence) przez REST API v1: odczyt i wyszukiwanie (CQL), tworzenie i edycja stron (storage format), komentarze, załączniki oraz eksport strony do notatki Obsidian.

## Skille
- **confluence-setup** — konfiguracja połączenia i test (`~/.confluence/config.json`).
- **confluence-read** — odczyt strony po ID/tytule, wyszukiwanie CQL, lista przestrzeni, komentarze.
- **confluence-write** — tworzenie i edycja stron (treść w storage format wprost), dodawanie komentarzy.
- **confluence-files** — upload i pobieranie załączników stron.
- **confluence-export** — eksport strony Confluence do notatki Markdown w vaultcie Obsidian (pandoc lub fallback).

## Instalacja
Zainstaluj przez marketplace pluginów Claude Code:

```
/plugin marketplace add lutencjusz/confluence-plugin
/plugin install confluence@confluence-plugin
```

Skille importują współdzielony moduł PowerShell (`lib/confluence.psm1`) przez `$env:CLAUDE_PLUGIN_ROOT`, więc plugin działa w każdym projekcie niezależnie od tego, gdzie Claude Code go zainstaluje — nie trzeba nic ręcznie podpinać.

## Wymagania
- Windows z PowerShell 7 (`pwsh`), `curl`.
- Token API Confluence Cloud z https://id.atlassian.com/manage-profile/security/api-tokens
- Pester 5 — tylko do uruchamiania testów, nie jest wymagany do korzystania ze skilli.
- Opcjonalnie `pandoc` — do konwersji storage → Markdown przy eksporcie (skill confluence-export); bez niego eksport zapisuje surowy storage w bloku ` ```html `.

## Konfiguracja
Uruchom skill **confluence-setup**, który utworzy `~/.confluence/config.json` (na Windows `%USERPROFILE%\.confluence\config.json`). Wzór: [`config.example.json`](config.example.json):

```json
{
  "baseUrl": "https://twoja-domena.atlassian.net/wiki",
  "email": "twoj-email@example.com",
  "apiToken": "xxxxxxxxxxxxxxxx"
}
```

| Pole | Znaczenie |
|------|-----------|
| `baseUrl` | bazowy URL wiki, bez końcowego `/` |
| `email` | e-mail konta Atlassian |
| `apiToken` | token API z https://id.atlassian.com/manage-profile/security/api-tokens |

## Przykładowe prompty
- „Skonfiguruj Confluence i sprawdź połączenie" → **confluence-setup**
- „Pokaż stronę Confluence o ID 123456" / „Znajdź stronę Home w przestrzeni DS" / „Szukaj w Confluence: text ~ n8n" / „Pokaż listę przestrzeni" / „Pokaż komentarze do strony 123456" → **confluence-read**
- „Utwórz stronę w przestrzeni DS pod tytułem Notatka" / „Zaktualizuj treść strony 123456" / „Dodaj komentarz do strony 123456" → **confluence-write**
- „Dodaj załącznik raport.pdf do strony 123456" / „Pobierz załącznik raport.pdf ze strony 123456" → **confluence-files**
- „Wyeksportuj stronę Confluence 123456 do Obsidian" → **confluence-export**

## ⚠️ Bezpieczeństwo
- Token API **nigdy nie trafia do argumentów procesu** — przekazywany jest do `curl` przez stdin (`-K -`), więc nie widać go np. w liście procesów.
- **Nie commituj** `config.json` — plik i tak żyje poza repo (`~/.confluence`), a `.gitignore` w tym repo dodatkowo chroni przed przypadkowym wrzuceniem sekretów lokalnie.
- Skille nigdy nie wypisują `apiToken` w odpowiedzi; przy błędzie 401/403 zgłaszają tylko zły token/e-mail, bez ujawniania wartości.

## Testy
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"
```
