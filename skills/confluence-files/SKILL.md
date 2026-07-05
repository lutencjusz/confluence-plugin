---
name: confluence-files
description: Use when uploading or downloading Confluence page attachments — attaching a local file to a page or downloading an attachment by filename. Triggers: "dodaj załącznik do strony Confluence", "wyślij plik na stronę", "pobierz załącznik z Confluence".
---

# confluence-files

Upload i pobieranie załączników stron Confluence Cloud.

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/confluence.psm1" -Force

# Upload załącznika do strony (nadpisuje = nowa wersja załącznika)
Send-ConfluenceAttachment -PageId '123456' -Path 'C:\dane\raport.pdf' -Comment 'Raport Q3'

# Pobranie załącznika po nazwie
Get-ConfluenceAttachment -PageId '123456' -Filename 'raport.pdf' -OutFile 'C:\dane\raport.pdf'
```

## Zasady
- Upload używa nagłówka `X-Atlassian-Token: nocheck` (wymagany przez API — dokładany automatycznie).
- Ponowny upload pliku o tej samej nazwie tworzy **nową wersję** załącznika.
- Przed uploadem/nadpisaniem potwierdź z użytkownikiem nazwę pliku i stronę docelową.
- Brak konfiguracji → odeślij do skilla confluence-setup.
