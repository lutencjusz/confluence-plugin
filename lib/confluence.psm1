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
