---
name: confluence-export
description: Use when exporting a Confluence Cloud page into an Obsidian Markdown note — fetching a page and saving it as a .md file with frontmatter. Triggers: "wyeksportuj stronę Confluence do Obsidian", "zapisz stronę jako notatkę .md", "ściągnij stronę Confluence do vaultu".
---

# confluence-export

Eksportuje stronę Confluence Cloud do notatki Markdown w vaultcie Obsidian.

## Procedura

1. Pobierz stronę:
   ```powershell
   Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/confluence.psm1" -Force
   $cfg = Get-ConfluenceConfig
   $p = Get-ConfluencePage -Id '123456' -Config $cfg
   $storage = $p.body.storage.value
   $spaceKey = $p.space.key
   $url = "$($cfg.baseUrl.TrimEnd('/'))/spaces/$spaceKey/pages/$($p.id)"
   ```
2. Konwersja treści:
   - jeśli `pandoc` dostępny (`Get-Command pandoc -ErrorAction SilentlyContinue`):
     ```powershell
     $md = $storage | pandoc -f html -t gfm
     ```
   - w przeciwnym razie **fallback** — surowy storage w bloku ` ```html `:
     ```powershell
     $md = "``````html`n$storage`n``````"
     ```
3. Zbuduj notatkę z frontmatterem i zapisz przez skill **obsidian-markdown**
   (wikilinki/tagi/frontmatter zgodnie z zasadami vaultu):
   ```yaml
   ---
   title: <p.title>
   url: <url>
   spaceKey: <spaceKey>
   confluenceId: <p.id>
   version: <p.version.number>
   source: confluence
   ---
   ```
4. Zaproponuj ścieżkę zapisu w vaultcie (katalog + `<tytuł>.md`) i potwierdź z użytkownikiem.

## Zasady
- Pandoc bywa stratny przy złożonych makrach Confluence — przy fallbacku zachowujesz pełny storage.
- Do zapisu notatki użyj skilla **obsidian-markdown** (nie zapisuj surowego pliku z pominięciem konwencji vaultu).
- Brak konfiguracji → odeślij do skilla confluence-setup.
