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
