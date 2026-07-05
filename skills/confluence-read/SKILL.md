---
name: confluence-read
description: Use when reading or searching Confluence Cloud content — fetching a page by ID or title (storage body), listing spaces, running a CQL search, or reading a page's comments. Triggers: "pokaż stronę Confluence", "znajdź stronę", "szukaj w Confluence (CQL)", "lista przestrzeni", "komentarze do strony".
---

# confluence-read

Odczyt i wyszukiwanie treści w Confluence Cloud (REST API v1).

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/confluence.psm1" -Force

# Strona po ID (z treścią storage)
$p = Get-ConfluencePage -Id '123456'
$p.title; $p.body.storage.value

# Znajdź stronę po tytule (opcjonalnie w danej przestrzeni)
Find-ConfluencePage -Title 'Home' -SpaceKey 'DS'

# Wyszukiwanie CQL
Search-ConfluenceCql -Cql 'text ~ "n8n" and type = page' -Limit 10

# Lista przestrzeni
Get-ConfluenceSpaces -Limit 25

# Komentarze do strony
Get-ConfluenceComments -PageId '123456'
```

## Zasady
- Funkcje zwracają sparsowany JSON — przedstaw dane czytelnie, nie surowym dumpem.
- Treść strony jest w `body.storage.value` (format storage = XHTML).
- Brak konfiguracji → odeślij do skilla confluence-setup.
- Składnia CQL: pola `type`, `space`, `title`, `text ~ "..."`, `created`, `lastmodified`.
