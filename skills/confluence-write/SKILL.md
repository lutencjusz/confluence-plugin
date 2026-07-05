---
name: confluence-write
description: 'Use when creating or editing Confluence Cloud pages (storage format) or adding a comment — new page in a space, updating an existing page's body, or posting a comment. Triggers: "utwórz stronę Confluence", "zaktualizuj stronę", "edytuj stronę Confluence", "dodaj komentarz do strony".'
---

# confluence-write

Tworzenie i edycja stron Confluence Cloud (**storage format wprost**) oraz komentarze.

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/confluence.psm1" -Force

# Nowa strona (treść w storage = XHTML)
New-ConfluencePage -SpaceKey 'DS' -Title 'Notatka' -Storage '<p>Treść strony</p>'

# Nowa strona-dziecko
New-ConfluencePage -SpaceKey 'DS' -Title 'Podstrona' -Storage '<p>...</p>' -ParentId '123456'

# Aktualizacja strony (wersja inkrementuje się automatycznie)
Update-ConfluencePage -Id '123456' -Storage '<p>Nowa treść</p>'

# Komentarz do strony
Add-ConfluenceComment -PageId '123456' -Storage '<p>Mój komentarz</p>'
```

## Zasady
- Treść podajesz w **storage format** (XHTML): akapity `<p>`, nagłówki `<h1>`–`<h6>`,
  listy `<ul>/<ol>`, tabele `<table>`, makra jako `<ac:structured-macro>`.
- `Update-ConfluencePage` sam pobiera bieżącą wersję i ją inkrementuje — nie podawaj numeru ręcznie.
- **Operacje zmieniające stan** (create/update/comment) — pokaż użytkownikowi tytuł/ID
  i treść, poproś o potwierdzenie przed wykonaniem.
- Brak konfiguracji → odeślij do skilla confluence-setup.
