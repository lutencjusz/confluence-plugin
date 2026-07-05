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
