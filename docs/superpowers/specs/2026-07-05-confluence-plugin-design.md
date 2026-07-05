# Confluence plugin — design

- **Data:** 2026-07-05
- **Autor:** lutencjusz (z Claude Code)
- **Wzorzec:** `mikrus-plugin` (PowerShell module + cienkie skille + Pester)
- **Cel:** Plugin Claude Code do obsługi Confluence Cloud instancji
  `https://lutencjusz.atlassian.net/wiki` przez REST API.

## 1. Kontekst i decyzje

Użytkownik wskazał docs `REST/6.6.0/` (Confluence **Server/DC**), ale realna instancja
to **Confluence Cloud** (`*.atlassian.net/wiki`). Projektujemy pod Cloud.

Rozstrzygnięcia podjęte w brainstormingu:

| Decyzja | Wybór | Uzasadnienie |
|---------|-------|--------------|
| Platforma | Confluence **Cloud** | realny serwer użytkownika |
| Wersja API | **v1 jednolicie** (`/wiki/rest/api`) | jeden base path pokrywa wszystkie 4 zakresy; najbliższe duchowi Mikrusa; v1 nie jest deprecated dla Cloud |
| Autoryzacja | Basic `email:token` | token z `id.atlassian.com`; sekret **przez stdin curl** (`-K -`), nigdy w linii poleceń |
| Format treści | **storage wprost** (XHTML) | zero maszynerii konwersji przy zapisie/odczycie |
| Eksport do vaultu | pandoc jeśli obecny, inaczej fallback surowy storage w bloku ` ```html ` | jedyny element z (best-effort) konwersją |
| Stack | PowerShell 7 + `curl.exe`, Pester 5 | 1:1 z Mikrusem |

Zakres pierwszej wersji (wszystkie zaznaczone): odczyt/wyszukiwanie, tworzenie/edycja
stron, komentarze i załączniki, eksport do Obsidian.

## 2. Lokalizacja

- Repo lokalne: `C:\claude\confluence-plugin` (git, gałąź `master`)
- GitHub: `https://github.com/lutencjusz/confluence-plugin` (publiczny, docelowo)
- Moduł: `lib/confluence.psm1`
- Konfiguracja: `~/.confluence/config.json` (poza repo, w `.gitignore`)
- Notatka dokumentacyjna w vaultcie: `AI/plugins/Confluence plugin.md`

## 3. Architektura

```
Prompt użytkownika → Skill → lib/confluence.psm1 → curl.exe (-K -, sekret przez stdin)
                                     ↓                        ↓
                        ~/.confluence/config.json    lutencjusz.atlassian.net/wiki/rest/api
```

Skille są cienkie: importują moduł przez `$env:CLAUDE_PLUGIN_ROOT` i wołają funkcję.
Cała logika (budowa URL, auth, parsowanie, obsługa błędów) siedzi w module.

## 4. Konfiguracja — `~/.confluence/config.json`

```json
{
  "baseUrl": "https://lutencjusz.atlassian.net/wiki",
  "email": "lutencjusz@gmail.com",
  "apiToken": "xxxxxxxxxxxxxxxx"
}
```

| Pole | Znaczenie | Źródło |
|------|-----------|--------|
| `baseUrl` | bazowy URL wiki (bez końcowego `/`) | instancja |
| `email` | e-mail konta Atlassian | konto |
| `apiToken` | token API | `id.atlassian.com/manage-profile/security/api-tokens` |

`apiToken` jest **wrażliwy** — nigdy nie wypisywać w odpowiedzi/logach, nie commitować.

## 5. Moduł `lib/confluence.psm1`

Funkcje infrastrukturalne:

- `Get-ConfluenceConfig [-Path]` — wczytanie + walidacja wymaganych pól
  (`baseUrl`, `email`, `apiToken`); rzuca czytelny wyjątek → odsyła do `confluence-setup`.
- `New-ConfluenceApiRequest -Config -Path [-Query]` — budowa pełnego URL
  z `baseUrl` + ścieżka + query string.
- `Invoke-ConfluenceCurl` — **mockowalny** rdzeń. Buduje argumenty curl:
  - metoda GET/POST/PUT, `-s`;
  - sekret przez `-K -` na stdin: linia `user = "email:token"` (+ ew. dodatkowe nagłówki);
  - JSON body: `--data @-`/`--data` z `Content-Type: application/json`;
  - multipart (upload): `-F file=@ścieżka` + nagłówek `X-Atlassian-Token: nocheck`.
- `Invoke-ConfluenceApi -Method -Path [-Body] [-Query] [-Config]` — wrapper:
  parsuje JSON, wykrywa błąd Cloud (`statusCode` != 2xx lub pole `message`),
  rzuca czytelny wyjątek.

Funkcje domenowe:

| Funkcja | Endpoint (v1) | Uwagi |
|---------|---------------|-------|
| `Get-ConfluencePage -Id` | `GET /content/{id}?expand=body.storage,version,space` | zwraca tytuł, storage, wersję |
| `Find-ConfluencePage -Title -SpaceKey` | `GET /content?title=&spaceKey=&expand=version` | wyszukanie po tytule |
| `Search-ConfluenceCql -Cql [-Limit]` | `GET /content/search?cql=` | wyszukiwanie CQL |
| `Get-ConfluenceSpaces [-Limit]` | `GET /space` | lista przestrzeni |
| `New-ConfluencePage -SpaceKey -Title -Storage [-ParentId]` | `POST /content` | `type=page`, body.storage |
| `Update-ConfluencePage -Id -Storage [-Title]` | `PUT /content/{id}` | **auto-pobranie bieżącej `version.number` i `++`** |
| `Add-ConfluenceComment -PageId -Storage` | `POST /content` | `type=comment`, `container` = strona |
| `Get-ConfluenceComments -PageId` | `GET /content/{id}/child/comment?expand=body.storage` | |
| `Send-ConfluenceAttachment -PageId -Path [-Comment]` | `POST /content/{id}/child/attachment` | multipart + `X-Atlassian-Token: nocheck` |
| `Get-ConfluenceAttachment -PageId -Filename -OutFile` | `GET /content/{id}/child/attachment` → download | pobranie po nazwie |

Gotcha (utrwalone z docs Cloud):
- **Update strony** wymaga inkrementacji `version.number` — `Update-ConfluencePage`
  robi to samodzielnie (pobiera obecną wersję, dodaje 1).
- **Upload załącznika** wymaga nagłówka `X-Atlassian-Token: nocheck`, inaczej 403.

## 6. Skille (5)

| Skill | Zastosowanie | Kluczowe funkcje |
|-------|--------------|------------------|
| `confluence-setup` | zapis `config.json` + test połączenia | `Get-ConfluenceConfig`, `GET /user/current`, `Get-ConfluenceSpaces` |
| `confluence-read` | strona po ID/tytule (storage), lista spaces, CQL search, odczyt komentarzy | `Get-ConfluencePage`, `Find-ConfluencePage`, `Search-ConfluenceCql`, `Get-ConfluenceSpaces`, `Get-ConfluenceComments` |
| `confluence-write` | create/update strony (storage wprost), dodanie komentarza | `New-ConfluencePage`, `Update-ConfluencePage`, `Add-ConfluenceComment` |
| `confluence-files` | upload/download załączników | `Send-ConfluenceAttachment`, `Get-ConfluenceAttachment` |
| `confluence-export` | strona → notatka `.md` w vaultcie | `Get-ConfluencePage` + pandoc (fallback blok ` ```html `) |

Zasady wspólne (w każdym skillu): nigdy nie wypisywać `apiToken`; operacje zmieniające
stan (`New-`/`Update-`/`Add-`/`Send-`) potwierdzać przed wykonaniem; brak configu →
odesłać do `confluence-setup`.

### confluence-export — szczegół

1. Pobierz stronę (`Get-ConfluencePage`) — tytuł, storage, wersja, spaceKey, URL.
2. Frontmatter: `title`, `url` (`{baseUrl}/spaces/{spaceKey}/pages/{id}`), `spaceKey`, `id`, `version`, `source: confluence`.
3. Treść:
   - jeśli `pandoc` dostępny (`Get-Command pandoc`) → `pandoc -f html -t gfm` na storage;
   - inaczej → surowy storage w bloku ` ```html `.
4. Zapis do wskazanej ścieżki w vaultcie (domyślnie zaproponuj katalog/tytuł, potwierdź).

## 7. Testy — `tests/confluence.Tests.ps1`

Pester 5, **bez realnych wywołań sieci** (mock `Invoke-ConfluenceCurl`):

- budowa URL z `baseUrl` + ścieżka + query (`New-ConfluenceApiRequest`);
- `Update-ConfluencePage` inkrementuje `version.number` (mock zwraca wersję N → PUT z N+1);
- `Send-ConfluenceAttachment` dokłada nagłówek `X-Atlassian-Token: nocheck` i `-F file=@`;
- `Invoke-ConfluenceApi` mapuje błąd Cloud (`statusCode`/`message`) na wyjątek;
- `Get-ConfluenceConfig` waliduje brakujące pola.

## 8. Pliki repo (docelowo)

```
.claude-plugin/plugin.json
.claude-plugin/marketplace.json
.gitignore                      # config.json, ~/.confluence, klucze
config.example.json
lib/confluence.psm1
skills/confluence-setup/SKILL.md
skills/confluence-read/SKILL.md
skills/confluence-write/SKILL.md
skills/confluence-files/SKILL.md
skills/confluence-export/SKILL.md
tests/confluence.Tests.ps1
README.md
README_PL.md
LICENSE                         # MIT
docs/superpowers/specs/2026-07-05-confluence-plugin-design.md
```

Dodatkowo w vaultcie Obsidian: `AI/plugins/Confluence plugin.md` (dokumentacja
w stylu `Mikrus plugin.md`).

## 9. Zakres świadomie pominięty (YAGNI)

- Konwersja Markdown→storage przy zapisie (piszemy storage wprost).
- Zarządzanie użytkownikami/uprawnieniami, webhooki.
- API v2 (`/wiki/api/v2/`) — v1 wystarcza dla wszystkich 4 zakresów.
- Labels, page tree/move, wersjonowanie ponad auto-increment przy update.
