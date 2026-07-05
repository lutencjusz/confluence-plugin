# Confluence Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zbudować plugin Claude Code do obsługi Confluence Cloud (`lutencjusz.atlassian.net/wiki`) przez REST API v1: odczyt/wyszukiwanie, tworzenie/edycja stron (storage wprost), komentarze, załączniki i eksport strony do notatki Obsidian.

**Architecture:** Cienkie skille aktywowane promptem importują jeden moduł PowerShell (`lib/confluence.psm1`), który buduje żądania i woła `curl.exe`. Sekret (`email:token`) idzie do curl przez stdin (`-K -`), nigdy w linii poleceń. Jedyny punkt styku z siecią to mockowalna funkcja `Invoke-ConfluenceCurl`, dzięki czemu wszystkie testy Pester działają bez realnych wywołań API.

**Tech Stack:** PowerShell 7 (`pwsh`), `curl.exe`, Pester 5, Confluence Cloud REST API v1 (`/wiki/rest/api`).

## Global Constraints

- Platforma: **Confluence Cloud**, API **v1** jednolicie, base path `{baseUrl}/rest/api/`.
- Autoryzacja: Basic `email:token` — **wyłącznie** przez curl config na stdin (`-K -`), linia `user = "email:token"`. Sekret nie może trafić do argumentów procesu.
- Format treści stron: **storage** (XHTML) wprost — `representation: storage`. Bez konwersji Markdown→storage przy zapisie.
- `apiToken` jest wrażliwy: nigdy nie wypisywać w odpowiedzi/logach, nie commitować.
- Config poza repo: `~/.confluence/config.json` (pola: `baseUrl`, `email`, `apiToken`), w `.gitignore`.
- Update strony: `version.number` musi być inkrementowane (funkcja robi to sama).
- Upload załącznika: wymaga nagłówka `X-Atlassian-Token: nocheck`, inaczej 403.
- Nazwa modułu (dla `Import-Module`/`Mock -ModuleName`): `confluence`.
- Wszystkie testy Pester mockują `Invoke-ConfluenceCurl` — zero realnych wywołań sieci.
- Commity: wiadomości po polsku, konwencja jak w repo (`feat:`, `test:`, `docs:`, `chore:`).

---

### Task 1: Szkielet repo i metadane pluginu

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.gitignore`
- Create: `config.example.json`
- Create: `LICENSE`

**Interfaces:**
- Consumes: nic (pierwszy task).
- Produces: strukturę katalogu pluginu rozpoznawaną przez Claude Code (`.claude-plugin/plugin.json` z `name: confluence`).

- [ ] **Step 1: Utwórz `.claude-plugin/plugin.json`**

```json
{
  "name": "confluence",
  "version": "0.1.0",
  "description": "Obsługa Confluence Cloud: odczyt/wyszukiwanie (CQL), tworzenie i edycja stron (storage), komentarze, załączniki i eksport do Obsidian.",
  "author": {
    "name": "lutencjusz",
    "url": "https://github.com/lutencjusz"
  },
  "license": "MIT",
  "homepage": "https://github.com/lutencjusz/confluence-plugin",
  "repository": "https://github.com/lutencjusz/confluence-plugin",
  "keywords": ["confluence", "atlassian", "wiki", "rest-api", "cql", "obsidian"]
}
```

- [ ] **Step 2: Utwórz `.claude-plugin/marketplace.json`**

```json
{
  "name": "confluence-plugin",
  "owner": { "name": "lutencjusz", "url": "https://github.com/lutencjusz" },
  "plugins": [
    {
      "name": "confluence",
      "source": "./",
      "description": "Obsługa Confluence Cloud: odczyt/wyszukiwanie (CQL), tworzenie i edycja stron (storage), komentarze, załączniki i eksport do Obsidian.",
      "version": "0.1.0"
    }
  ]
}
```

- [ ] **Step 3: Utwórz `.gitignore`**

```gitignore
# Nigdy nie commituj sekretów ani lokalnej konfiguracji Confluence
config.json
.env
*.key
*.pem
.confluence/

# Pliki IDE (JetBrains)
.idea/
```

- [ ] **Step 4: Utwórz `config.example.json`**

```json
{
  "baseUrl": "https://lutencjusz.atlassian.net/wiki",
  "email": "twoj-email@example.com",
  "apiToken": "xxxxxxxxxxxxxxxx"
}
```

- [ ] **Step 5: Utwórz `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 lutencjusz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin config.example.json .gitignore LICENSE
git commit -m "chore: szkielet repo confluence-plugin i metadane"
```

---

### Task 2: `Get-ConfluenceConfig` + harness testów

**Files:**
- Create: `lib/confluence.psm1`
- Create: `tests/confluence.Tests.ps1`

**Interfaces:**
- Consumes: nic.
- Produces: `Get-ConfluenceConfig [-Path <string>] -> pscustomobject` z polami `baseUrl`, `email`, `apiToken`. Domyślny `-Path` = `~/.confluence/config.json`. Rzuca wyjątek z frazą `confluence-setup`, gdy brak pliku lub pola.

- [ ] **Step 1: Napisz test (`tests/confluence.Tests.ps1`)**

```powershell
Import-Module "$PSScriptRoot/../lib/confluence.psm1" -Force

Describe 'Modul confluence laduje sie' {
    It 'importuje sie bez bledu' {
        Get-Module confluence | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ConfluenceConfig' {
    BeforeAll {
        $script:validCfg = @{
            baseUrl = 'https://lutencjusz.atlassian.net/wiki'
            email   = 'a@b.c'
            apiToken = 'SECRET'
        }
    }

    It 'wczytuje poprawny config z pliku' {
        $path = Join-Path $TestDrive 'config.json'
        $script:validCfg | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        $cfg = Get-ConfluenceConfig -Path $path
        $cfg.baseUrl | Should -Be 'https://lutencjusz.atlassian.net/wiki'
        $cfg.email   | Should -Be 'a@b.c'
    }

    It 'rzuca blad z instrukcja confluence-setup gdy brak pliku' {
        $path = Join-Path $TestDrive 'nieistnieje.json'
        { Get-ConfluenceConfig -Path $path } | Should -Throw -ExpectedMessage '*confluence-setup*'
    }

    It 'rzuca blad gdy brakuje wymaganego pola' {
        $path = Join-Path $TestDrive 'incomplete.json'
        $incomplete = $script:validCfg.Clone(); $incomplete.Remove('apiToken')
        $incomplete | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        { Get-ConfluenceConfig -Path $path } | Should -Throw -ExpectedMessage '*apiToken*'
    }
}
```

- [ ] **Step 2: Uruchom test — ma NIE przejść (brak modułu/funkcji)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: FAIL — moduł/`Get-ConfluenceConfig` nie istnieje.

- [ ] **Step 3: Napisz minimalną implementację (`lib/confluence.psm1`)**

```powershell
# Modul obslugi Confluence Cloud (REST API v1).
# Konfiguracja: ~/.confluence/config.json (patrz skill confluence-setup).

Set-StrictMode -Version Latest

function Get-ConfluenceConfig {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $HOME '.confluence/config.json')
    )
    if (-not (Test-Path -Path $Path)) {
        throw "Brak konfiguracji Confluence ($Path). Uruchom skill confluence-setup, aby ja utworzyc."
    }
    $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json
    $required = 'baseUrl','email','apiToken'
    $missing = foreach ($f in $required) {
        $has = $cfg.PSObject.Properties.Name -contains $f
        if (-not $has -or [string]::IsNullOrWhiteSpace([string]$cfg.$f)) { $f }
    }
    if ($missing) {
        throw "Konfiguracja Confluence niekompletna ($Path). Brakuje pol: $($missing -join ', '). Uruchom confluence-setup."
    }
    return $cfg
}
```

- [ ] **Step 4: Uruchom test — ma przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS (4 testy).

- [ ] **Step 5: Commit**

```bash
git add lib/confluence.psm1 tests/confluence.Tests.ps1
git commit -m "feat: Get-ConfluenceConfig + harness testow Pester"
```

---

### Task 3: Warstwa HTTP — URL, curl config, `Invoke-ConfluenceApi`

**Files:**
- Modify: `lib/confluence.psm1`
- Modify: `tests/confluence.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ConfluenceConfig`.
- Produces:
  - `New-ConfluenceApiRequest -Config <obj> -Path <string> [-Query <hashtable>] -> string` (pełny URL `{baseUrl}/rest/api/{path}?...`).
  - `New-ConfluenceCurlConfig -Email <string> -ApiToken <string> [-NoCheck] -> string` (treść curl config na stdin; linia `user = "email:token"` + opcjonalnie `header = "X-Atlassian-Token: nocheck"`).
  - `Invoke-ConfluenceCurl -Method <GET|POST|PUT> -Url <string> -Email <string> -ApiToken <string> [-JsonBody <string>] [-FilePath <string>] [-AttachmentComment <string>] [-OutFile <string>] [-NoCheck] -> string` (mockowalny rdzeń sieci).
  - `Invoke-ConfluenceApi -Method <GET|POST|PUT> -Path <string> [-Query <hashtable>] [-Body <object>] [-FilePath <string>] [-AttachmentComment <string>] [-OutFile <string>] [-NoCheck] [-Config <obj>] -> object` (parsuje JSON, mapuje błąd Cloud na wyjątek).

- [ ] **Step 1: Napisz testy (dopisz nowe `Describe` do `tests/confluence.Tests.ps1`)**

```powershell
Describe 'New-ConfluenceApiRequest' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            baseUrl = 'https://lutencjusz.atlassian.net/wiki'; email='a@b.c'; apiToken='SECRET'
        }
    }
    It 'buduje URL z base path rest/api' {
        New-ConfluenceApiRequest -Config $script:cfg -Path 'content/123' |
            Should -Be 'https://lutencjusz.atlassian.net/wiki/rest/api/content/123'
    }
    It 'obcina koncowy slash z baseUrl i wiodacy z Path' {
        $c = [pscustomobject]@{ baseUrl='https://x.atlassian.net/wiki/'; email='a@b.c'; apiToken='S' }
        New-ConfluenceApiRequest -Config $c -Path '/space' |
            Should -Be 'https://x.atlassian.net/wiki/rest/api/space'
    }
    It 'dokleja i koduje query string' {
        $u = New-ConfluenceApiRequest -Config $script:cfg -Path 'content/search' -Query @{ cql = 'type=page' }
        $u | Should -Match '\?cql=type%3Dpage$'
    }
}

Describe 'New-ConfluenceCurlConfig' {
    It 'umieszcza poswiadczenia w linii user (sekret idzie przez stdin, nie argv)' {
        $c = New-ConfluenceCurlConfig -Email 'a@b.c' -ApiToken 'SECRET'
        $c | Should -Match 'user = "a@b.c:SECRET"'
    }
    It 'dodaje naglowek nocheck przy -NoCheck' {
        $c = New-ConfluenceCurlConfig -Email 'a@b.c' -ApiToken 'SECRET' -NoCheck
        $c | Should -Match 'X-Atlassian-Token: nocheck'
    }
    It 'bez -NoCheck nie ma naglowka nocheck' {
        $c = New-ConfluenceCurlConfig -Email 'a@b.c' -ApiToken 'SECRET'
        $c | Should -Not -Match 'nocheck'
    }
}

Describe 'Invoke-ConfluenceApi' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            baseUrl='https://x.atlassian.net/wiki'; email='a@b.c'; apiToken='SECRET'
        }
    }
    It 'parsuje poprawny JSON' {
        Mock -ModuleName confluence Invoke-ConfluenceCurl { '{"id":"1","title":"T"}' }
        $r = Invoke-ConfluenceApi -Method GET -Path 'content/1' -Config $script:cfg
        $r.title | Should -Be 'T'
    }
    It 'mapuje blad Cloud (statusCode>=400) na wyjatek z message' {
        Mock -ModuleName confluence Invoke-ConfluenceCurl { '{"statusCode":404,"message":"No content found"}' }
        { Invoke-ConfluenceApi -Method GET -Path 'content/999' -Config $script:cfg } |
            Should -Throw -ExpectedMessage '*No content found*'
    }
    It 'rzuca na niepoprawny JSON' {
        Mock -ModuleName confluence Invoke-ConfluenceCurl { '<html>500</html>' }
        { Invoke-ConfluenceApi -Method GET -Path 'content/1' -Config $script:cfg } |
            Should -Throw -ExpectedMessage '*Niepoprawna odpowiedz*'
    }
}
```

- [ ] **Step 2: Uruchom testy — mają NIE przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: FAIL — brak `New-ConfluenceApiRequest`/`New-ConfluenceCurlConfig`/`Invoke-ConfluenceApi`.

- [ ] **Step 3: Dopisz implementację do `lib/confluence.psm1`**

```powershell
function New-ConfluenceApiRequest {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query
    )
    $base = ([string]$Config.baseUrl).TrimEnd('/')
    $p    = $Path.TrimStart('/')
    $url  = "$base/rest/api/$p"
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($k in $Query.Keys) {
            "$k=$([uri]::EscapeDataString([string]$Query[$k]))"
        }
        $url = "$url`?$($pairs -join '&')"
    }
    return $url
}

function New-ConfluenceCurlConfig {
    # Tresc pliku konfiguracyjnego curl przekazywanego przez stdin (-K -).
    # Poswiadczenia w linii `user` NIE trafiaja do argumentow procesu.
    param(
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$ApiToken,
        [switch]$NoCheck
    )
    $lines = @("user = `"$Email`:$ApiToken`"")
    if ($NoCheck) { $lines += 'header = "X-Atlassian-Token: nocheck"' }
    return ($lines -join [Environment]::NewLine)
}

function Invoke-ConfluenceCurl {
    # Jedyny punkt styku z siecia (mockowalny w testach).
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$ApiToken,
        [string]$JsonBody,
        [string]$FilePath,
        [string]$AttachmentComment,
        [string]$OutFile,
        [switch]$NoCheck
    )
    $tmp = $null
    try {
        $curlArgs = @('-s', '-X', $Method, '-K', '-')
        if ($FilePath) {
            # Upload multipart. Nazwa pola 'file' wg API zalacznikow v1.
            $curlArgs += @('-F', "file=@$FilePath")
            if ($AttachmentComment) { $curlArgs += @('-F', "comment=$AttachmentComment") }
        } elseif ($JsonBody) {
            # JSON przez plik tymczasowy (@plik) — omija problemy z escapowaniem w argv.
            $tmp = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tmp -Value $JsonBody -Encoding utf8 -NoNewline
            $curlArgs += @('-H', 'Content-Type: application/json', '--data', "@$tmp")
        }
        if ($OutFile) { $curlArgs += @('-L', '-o', $OutFile) }
        $curlArgs += $Url
        $config = New-ConfluenceCurlConfig -Email $Email -ApiToken $ApiToken -NoCheck:$NoCheck
        return ($config | & curl.exe @curlArgs)
    } finally {
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-ConfluenceApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query,
        $Body,
        [string]$FilePath,
        [string]$AttachmentComment,
        [string]$OutFile,
        [switch]$NoCheck,
        $Config
    )
    if (-not $Config) { $Config = Get-ConfluenceConfig }
    $url  = New-ConfluenceApiRequest -Config $Config -Path $Path -Query $Query
    $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }
    $raw  = Invoke-ConfluenceCurl -Method $Method -Url $url -Email $Config.email -ApiToken $Config.apiToken `
                -JsonBody $json -FilePath $FilePath -AttachmentComment $AttachmentComment -OutFile $OutFile -NoCheck:$NoCheck
    if ($OutFile) { return $OutFile }  # pobranie do pliku — brak tresci JSON
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $null }
    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Niepoprawna odpowiedz API ($Path): $raw"
    }
    if (($data -is [pscustomobject]) -and ($data.PSObject.Properties.Name -contains 'statusCode') -and ([int]$data.statusCode -ge 400)) {
        $msg = if ($data.PSObject.Properties.Name -contains 'message') { $data.message } else { "statusCode $($data.statusCode)" }
        throw "API Confluence blad ($Path): $msg"
    }
    return $data
}
```

- [ ] **Step 4: Uruchom testy — mają przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS (wszystkie z Task 2 + nowe z Task 3).

- [ ] **Step 5: Commit**

```bash
git add lib/confluence.psm1 tests/confluence.Tests.ps1
git commit -m "feat: warstwa HTTP (URL builder, curl config na stdin, Invoke-ConfluenceApi)"
```

---

### Task 4: Funkcje odczytu i wyszukiwania

**Files:**
- Modify: `lib/confluence.psm1`
- Modify: `tests/confluence.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-ConfluenceApi`.
- Produces:
  - `Get-ConfluencePage -Id <string> [-Config] -> object` (expand `body.storage,version,space`).
  - `Find-ConfluencePage -Title <string> [-SpaceKey <string>] [-Config] -> object`.
  - `Search-ConfluenceCql -Cql <string> [-Limit <int>] [-Config] -> object`.
  - `Get-ConfluenceSpaces [-Limit <int>] [-Config] -> object`.
  - `Get-ConfluenceComments -PageId <string> [-Config] -> object`.

- [ ] **Step 1: Napisz testy (dopisz `Describe` do testów)**

```powershell
Describe 'Funkcje odczytu' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{ baseUrl='https://x.atlassian.net/wiki'; email='a@b.c'; apiToken='S' }
    }
    It 'Get-ConfluencePage woła GET content/{id} z expand body.storage' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"ok":1}' } -ParameterFilter {
            $Method -eq 'GET' -and $Path -eq 'content/123' -and $Query.expand -like '*body.storage*'
        }
        Get-ConfluencePage -Id '123' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }
    It 'Search-ConfluenceCql przekazuje cql i limit' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"results":[]}' } -ParameterFilter {
            $Path -eq 'content/search' -and $Query.cql -eq 'text ~ "foo"' -and $Query.limit -eq 10
        }
        Search-ConfluenceCql -Cql 'text ~ "foo"' -Limit 10 -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }
    It 'Find-ConfluencePage dodaje spaceKey gdy podany' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"results":[]}' } -ParameterFilter {
            $Path -eq 'content' -and $Query.title -eq 'Home' -and $Query.spaceKey -eq 'DS'
        }
        Find-ConfluencePage -Title 'Home' -SpaceKey 'DS' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }
}
```

Uwaga: mock `Invoke-ConfluenceApi` zwraca string, ale funkcje po prostu go przekazują — testujemy przekazane parametry przez `-ParameterFilter`.

- [ ] **Step 2: Uruchom testy — mają NIE przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: FAIL — brak funkcji odczytu.

- [ ] **Step 3: Dopisz implementację do `lib/confluence.psm1`**

```powershell
function Get-ConfluencePage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, $Config)
    return Invoke-ConfluenceApi -Method GET -Path "content/$Id" -Query @{ expand = 'body.storage,version,space' } -Config $Config
}

function Find-ConfluencePage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title, [string]$SpaceKey, $Config)
    $q = @{ title = $Title; expand = 'version,space' }
    if ($SpaceKey) { $q.spaceKey = $SpaceKey }
    return Invoke-ConfluenceApi -Method GET -Path 'content' -Query $q -Config $Config
}

function Search-ConfluenceCql {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Cql, [int]$Limit = 25, $Config)
    return Invoke-ConfluenceApi -Method GET -Path 'content/search' -Query @{ cql = $Cql; limit = $Limit } -Config $Config
}

function Get-ConfluenceSpaces {
    [CmdletBinding()]
    param([int]$Limit = 25, $Config)
    return Invoke-ConfluenceApi -Method GET -Path 'space' -Query @{ limit = $Limit } -Config $Config
}

function Get-ConfluenceComments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PageId, $Config)
    return Invoke-ConfluenceApi -Method GET -Path "content/$PageId/child/comment" -Query @{ expand = 'body.storage,version' } -Config $Config
}
```

- [ ] **Step 4: Uruchom testy — mają przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/confluence.psm1 tests/confluence.Tests.ps1
git commit -m "feat: funkcje odczytu (page, find, CQL search, spaces, comments)"
```

---

### Task 5: Funkcje zapisu (create/update/comment)

**Files:**
- Modify: `lib/confluence.psm1`
- Modify: `tests/confluence.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-ConfluenceApi`, `Get-ConfluencePage`.
- Produces:
  - `New-ConfluencePage -SpaceKey <string> -Title <string> -Storage <string> [-ParentId <string>] [-Config] -> object`.
  - `Update-ConfluencePage -Id <string> -Storage <string> [-Title <string>] [-Config] -> object` (auto `version.number+1`).
  - `Add-ConfluenceComment -PageId <string> -Storage <string> [-Config] -> object`.

- [ ] **Step 1: Napisz testy**

```powershell
Describe 'Funkcje zapisu' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{ baseUrl='https://x.atlassian.net/wiki'; email='a@b.c'; apiToken='S' }
    }

    It 'New-ConfluencePage buduje body z type=page i storage' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"id":"1"}' } -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'content' -and
            $Body.type -eq 'page' -and $Body.space.key -eq 'DS' -and
            $Body.body.storage.representation -eq 'storage' -and
            $Body.body.storage.value -eq '<p>hi</p>'
        }
        New-ConfluencePage -SpaceKey 'DS' -Title 'T' -Storage '<p>hi</p>' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }

    It 'New-ConfluencePage dodaje ancestors gdy ParentId' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"id":"1"}' } -ParameterFilter {
            $Body.ancestors[0].id -eq '999'
        }
        New-ConfluencePage -SpaceKey 'DS' -Title 'T' -Storage '<p>x</p>' -ParentId '999' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }

    It 'Update-ConfluencePage inkrementuje version.number (N -> N+1)' {
        # GET (obecna wersja) i PUT ida przez Invoke-ConfluenceApi — rozroznij po Method.
        Mock -ModuleName confluence Invoke-ConfluenceApi {
            if ($Method -eq 'GET') {
                return ([pscustomobject]@{ id='123'; title='Stary'; version=[pscustomobject]@{ number=5 } })
            }
            return ([pscustomobject]@{ id='123' })
        }
        Update-ConfluencePage -Id '123' -Storage '<p>new</p>' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Path -eq 'content/123' -and $Body.version.number -eq 6
        }
    }

    It 'Update-ConfluencePage zachowuje stary tytul gdy -Title nie podany' {
        Mock -ModuleName confluence Invoke-ConfluenceApi {
            if ($Method -eq 'GET') {
                return ([pscustomobject]@{ id='123'; title='Stary'; version=[pscustomobject]@{ number=1 } })
            }
            return ([pscustomobject]@{ id='123' })
        }
        Update-ConfluencePage -Id '123' -Storage '<p>x</p>' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Body.title -eq 'Stary'
        }
    }

    It 'Add-ConfluenceComment buduje type=comment z container=strona' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"id":"c1"}' } -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'content' -and
            $Body.type -eq 'comment' -and $Body.container.id -eq '123' -and $Body.container.type -eq 'page'
        }
        Add-ConfluenceComment -PageId '123' -Storage '<p>komentarz</p>' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }
}
```

- [ ] **Step 2: Uruchom testy — mają NIE przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: FAIL — brak funkcji zapisu.

- [ ] **Step 3: Dopisz implementację do `lib/confluence.psm1`**

```powershell
function New-ConfluencePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SpaceKey,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Storage,
        [string]$ParentId,
        $Config
    )
    $body = @{
        type  = 'page'
        title = $Title
        space = @{ key = $SpaceKey }
        body  = @{ storage = @{ value = $Storage; representation = 'storage' } }
    }
    if ($ParentId) { $body.ancestors = @(@{ id = $ParentId }) }
    return Invoke-ConfluenceApi -Method POST -Path 'content' -Body $body -Config $Config
}

function Update-ConfluencePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Storage,
        [string]$Title,
        $Config
    )
    if (-not $Config) { $Config = Get-ConfluenceConfig }
    $current = Get-ConfluencePage -Id $Id -Config $Config
    $nextVersion = [int]$current.version.number + 1
    $newTitle = if ($Title) { $Title } else { $current.title }
    $body = @{
        id      = $Id
        type    = 'page'
        title   = $newTitle
        body    = @{ storage = @{ value = $Storage; representation = 'storage' } }
        version = @{ number = $nextVersion }
    }
    return Invoke-ConfluenceApi -Method PUT -Path "content/$Id" -Body $body -Config $Config
}

function Add-ConfluenceComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$Storage,
        $Config
    )
    $body = @{
        type      = 'comment'
        container = @{ id = $PageId; type = 'page' }
        body      = @{ storage = @{ value = $Storage; representation = 'storage' } }
    }
    return Invoke-ConfluenceApi -Method POST -Path 'content' -Body $body -Config $Config
}
```

- [ ] **Step 4: Uruchom testy — mają przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/confluence.psm1 tests/confluence.Tests.ps1
git commit -m "feat: funkcje zapisu (create/update strony z auto-wersja, komentarz)"
```

---

### Task 6: Załączniki (upload/download)

**Files:**
- Modify: `lib/confluence.psm1`
- Modify: `tests/confluence.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-ConfluenceApi`, `Invoke-ConfluenceCurl`, `Get-ConfluenceConfig`, `New-ConfluenceCurlConfig`.
- Produces:
  - `Send-ConfluenceAttachment -PageId <string> -Path <string> [-Comment <string>] [-Config] -> object` (multipart + `-NoCheck`).
  - `Get-ConfluenceAttachment -PageId <string> -Filename <string> -OutFile <string> [-Config] -> string` (ścieżka zapisanego pliku).

- [ ] **Step 1: Napisz testy**

```powershell
Describe 'Zalaczniki' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{ baseUrl='https://x.atlassian.net/wiki'; email='a@b.c'; apiToken='S' }
    }

    It 'Send-ConfluenceAttachment uzywa FilePath i -NoCheck (naglowek nocheck)' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { '{"results":[{"id":"att1"}]}' } -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'content/123/child/attachment' -and
            $FilePath -eq 'C:\dane\plik.txt' -and $NoCheck -eq $true
        }
        Send-ConfluenceAttachment -PageId '123' -Path 'C:\dane\plik.txt' -Config $script:cfg | Out-Null
        Should -Invoke -ModuleName confluence Invoke-ConfluenceApi -Times 1
    }

    It 'Get-ConfluenceAttachment sciaga po nazwie do OutFile' {
        Mock -ModuleName confluence Invoke-ConfluenceApi {
            [pscustomobject]@{ results = @(
                [pscustomobject]@{ title='plik.txt'; _links = [pscustomobject]@{ download = '/download/attachments/123/plik.txt?version=1' } }
            ) }
        } -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'content/123/child/attachment' }
        Mock -ModuleName confluence Invoke-ConfluenceCurl { '' } -ParameterFilter {
            $OutFile -eq 'C:\out\plik.txt' -and $Url -like '*download/attachments/123/plik.txt*'
        }
        $r = Get-ConfluenceAttachment -PageId '123' -Filename 'plik.txt' -OutFile 'C:\out\plik.txt' -Config $script:cfg
        $r | Should -Be 'C:\out\plik.txt'
        Should -Invoke -ModuleName confluence Invoke-ConfluenceCurl -Times 1
    }

    It 'Get-ConfluenceAttachment rzuca gdy brak zalacznika o nazwie' {
        Mock -ModuleName confluence Invoke-ConfluenceApi { [pscustomobject]@{ results = @() } }
        { Get-ConfluenceAttachment -PageId '123' -Filename 'brak.txt' -OutFile 'C:\out\brak.txt' -Config $script:cfg } |
            Should -Throw -ExpectedMessage '*brak.txt*'
    }
}
```

- [ ] **Step 2: Uruchom testy — mają NIE przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: FAIL — brak funkcji załączników.

- [ ] **Step 3: Dopisz implementację do `lib/confluence.psm1`**

```powershell
function Send-ConfluenceAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$Path,
        [string]$Comment,
        $Config
    )
    return Invoke-ConfluenceApi -Method POST -Path "content/$PageId/child/attachment" `
        -FilePath $Path -AttachmentComment $Comment -NoCheck -Config $Config
}

function Get-ConfluenceAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$Filename,
        [Parameter(Mandatory)][string]$OutFile,
        $Config
    )
    if (-not $Config) { $Config = Get-ConfluenceConfig }
    $list = Invoke-ConfluenceApi -Method GET -Path "content/$PageId/child/attachment" -Query @{ filename = $Filename } -Config $Config
    $att = $list.results | Where-Object { $_.title -eq $Filename } | Select-Object -First 1
    if (-not $att) { throw "Nie znaleziono zalacznika '$Filename' na stronie $PageId." }
    $downloadUrl = ([string]$Config.baseUrl).TrimEnd('/') + [string]$att._links.download
    $null = Invoke-ConfluenceCurl -Method GET -Url $downloadUrl -Email $Config.email -ApiToken $Config.apiToken -OutFile $OutFile
    return $OutFile
}
```

Uwaga: `_links.download` z v1 jest względny wobec `{baseUrl}` (czyli `.../wiki`), więc doklejamy go do `baseUrl`.

- [ ] **Step 4: Uruchom testy — mają przejść**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS (cały plik testów).

- [ ] **Step 5: Commit**

```bash
git add lib/confluence.psm1 tests/confluence.Tests.ps1
git commit -m "feat: zalaczniki (upload z nocheck, download po nazwie)"
```

---

### Task 7: Skille (5 plików `SKILL.md`)

**Files:**
- Create: `skills/confluence-setup/SKILL.md`
- Create: `skills/confluence-read/SKILL.md`
- Create: `skills/confluence-write/SKILL.md`
- Create: `skills/confluence-files/SKILL.md`
- Create: `skills/confluence-export/SKILL.md`

**Interfaces:**
- Consumes: wszystkie funkcje modułu z Task 2–6.
- Produces: cienkie skille aktywowane promptem; każdy importuje moduł przez `$env:CLAUDE_PLUGIN_ROOT`.

- [ ] **Step 1: `skills/confluence-setup/SKILL.md`**

````markdown
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
````

- [ ] **Step 2: `skills/confluence-read/SKILL.md`**

````markdown
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
````

- [ ] **Step 3: `skills/confluence-write/SKILL.md`**

````markdown
---
name: confluence-write
description: Use when creating or editing Confluence Cloud pages (storage format) or adding a comment — new page in a space, updating an existing page's body, or posting a comment. Triggers: "utwórz stronę Confluence", "zaktualizuj stronę", "edytuj stronę Confluence", "dodaj komentarz do strony".
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
````

- [ ] **Step 4: `skills/confluence-files/SKILL.md`**

````markdown
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
````

- [ ] **Step 5: `skills/confluence-export/SKILL.md`**

````markdown
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
````

- [ ] **Step 6: Sanity-check — moduł eksportuje wszystkie funkcje używane w skillach**

Run:
```
pwsh -NoProfile -Command "Import-Module ./lib/confluence.psm1 -Force; 'Get-ConfluenceConfig','Get-ConfluencePage','Find-ConfluencePage','Search-ConfluenceCql','Get-ConfluenceSpaces','Get-ConfluenceComments','New-ConfluencePage','Update-ConfluencePage','Add-ConfluenceComment','Send-ConfluenceAttachment','Get-ConfluenceAttachment' | ForEach-Object { '{0} -> {1}' -f $_, [bool](Get-Command $_ -ErrorAction SilentlyContinue) }"
```
Expected: każda funkcja `-> True`.

- [ ] **Step 7: Commit**

```bash
git add skills/
git commit -m "feat: 5 skilli (setup, read, write, files, export)"
```

---

### Task 8: README + notatka dokumentacyjna w vaultcie

**Files:**
- Create: `README.md`
- Create: `README_PL.md`
- Create (w vaultcie Obsidian): `C:\Data\Obsidian\Obsidian\AI\plugins\Confluence plugin.md`

**Interfaces:**
- Consumes: cały plugin.
- Produces: dokumentację użytkownika + wpięcie w graf vaultu.

- [ ] **Step 1: `README_PL.md`**

Opisz: cel, wymagania (PowerShell 7, curl, token API), instalację przez marketplace
(`/plugin marketplace add lutencjusz/confluence-plugin`, `/plugin install confluence@confluence-plugin`),
konfigurację (`~/.confluence/config.json` z tabelą pól), listę 5 skilli z przykładowymi
promptami, uruchomienie testów (`Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed`),
oraz sekcję bezpieczeństwa (token przez stdin, `.gitignore`, nie wypisywać `apiToken`).
Wzoruj się układem na `C:\claude\mikrus-plugin\README_PL.md`.

- [ ] **Step 2: `README.md`**

Skrócona wersja angielska (ten sam układ), z odnośnikiem do `README_PL.md` po polską wersję.

- [ ] **Step 3: Notatka w vaultcie `AI/plugins/Confluence plugin.md`**

Utwórz notatkę w stylu `AI/plugins/Mikrus plugin.md` (frontmatter: `title`, `date: 2026-07-05`,
tagi `claude-code`, `plugin`, `confluence`, `atlassian`; aliasy `Plugin Confluence`, `confluence-plugin`).
Sekcje: opis, lokalizacja (repo `C:\claude\confluence-plugin`, GitHub, moduł `lib/confluence.psm1`,
config `~/.confluence/config.json`), wymagania, instalacja, konfiguracja (tabela pól),
tabela 5 skilli z `[[wikilinkami]]` do nagłówków, przykładowe prompty (callouty `> [!example]`),
callout bezpieczeństwa `> [!danger]` (token wrażliwy), diagram `mermaid` architektury,
sekcja „Powiązane" z linkami (GitHub, docs Atlassian Cloud, panel tokenów, spec).
Użyj skilla **obsidian-markdown** do zapisu (wikilinki, callouty, frontmatter).

- [ ] **Step 4: Uruchom pełne testy jeszcze raz (regresja)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/confluence.Tests.ps1 -Output Detailed"`
Expected: PASS — cały zestaw.

- [ ] **Step 5: Commit (repo pluginu)**

```bash
git add README.md README_PL.md
git commit -m "docs: README (PL/EN) confluence-plugin"
```

Uwaga: notatka `AI/plugins/Confluence plugin.md` jest w vaultcie Obsidian — **nie commituj
jej ręcznie**; backup vaultu idzie skillem `obsidian-backup`, commit vaultu poza zakresem tego pluginu.

---

## Uwagi końcowe dla wykonawcy

- Po każdym tasku uruchamiaj pełny plik testów, nie tylko nowe `Describe` — chroni przed regresją.
- Realne wywołania API (`Get-ConfluenceSpaces` na żywo) rób dopiero po `confluence-setup`
  z prawdziwym tokenem — testy Pester ich nie pokrywają (celowo, mock).
- Push do GitHub (`git remote add origin ...`, `git push`) tylko po wyraźnej zgodzie użytkownika.
