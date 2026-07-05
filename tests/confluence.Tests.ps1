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

Describe 'New-ConfluenceCurlArgs' {
    It 'nie przyjmuje parametrow z poswiadczeniami (Email/ApiToken pozostaja tylko w New-ConfluenceCurlConfig)' {
        $params = (Get-Command New-ConfluenceCurlArgs).Parameters.Keys
        $params | Should -Not -Contain 'Email'
        $params | Should -Not -Contain 'ApiToken'
    }

    It 'buduje argumenty dla JSON body (plik tymczasowy przez -DataFile, bez --fail)' {
        $a = New-ConfluenceCurlArgs -Method 'POST' -Url 'https://x.atlassian.net/wiki/rest/api/content' -DataFile 'C:\tmp\body.json'
        $a | Should -Contain '--data'
        $a | Should -Contain '@C:\tmp\body.json'
        $a | Should -Contain 'Content-Type: application/json'
        $a | Should -Not -Contain '--fail'
        ($a -join ' ') | Should -Not -Match 'a@b\.c|SECRET'
    }

    It 'buduje argumenty dla multipart -FilePath (bez --fail)' {
        $a = New-ConfluenceCurlArgs -Method 'POST' -Url 'https://x.atlassian.net/wiki/rest/api/content/123/child/attachment' -FilePath 'C:\dane\plik.txt' -AttachmentComment 'komentarz'
        $a | Should -Contain '-F'
        $a | Should -Contain 'file=@C:\dane\plik.txt'
        $a | Should -Contain 'comment=komentarz'
        $a | Should -Not -Contain '--fail'
        ($a -join ' ') | Should -Not -Match 'a@b\.c|SECRET'
    }

    It 'buduje argumenty dla pobrania -OutFile (z --fail, HTTP >=400 => brak pliku)' {
        $a = New-ConfluenceCurlArgs -Method 'GET' -Url 'https://x.atlassian.net/wiki/download/attachments/123/plik.txt' -OutFile 'C:\out\plik.txt'
        $a | Should -Contain '--fail'
        $a | Should -Contain '-L'
        $a | Should -Contain '-o'
        $a | Should -Contain 'C:\out\plik.txt'
        ($a -join ' ') | Should -Not -Match 'a@b\.c|SECRET'
    }
}

Describe 'Invoke-ConfluenceCurl — kontrola exit code' {
    It 'rzuca czytelny blad gdy curl konczy sie kodem != 0 (transport failure / --fail na download)' {
        Mock -ModuleName confluence curl.exe { $global:LASTEXITCODE = 22; return '' }
        { Invoke-ConfluenceCurl -Method GET -Url 'https://x.atlassian.net/wiki/rest/api/content/1' -Email 'a@b.c' -ApiToken 'SECRET' } |
            Should -Throw -ExpectedMessage '*kodem 22*'
    }

    It 'nie rzuca gdy curl konczy sie kodem 0' {
        Mock -ModuleName confluence curl.exe { $global:LASTEXITCODE = 0; return '{"id":"1"}' }
        { Invoke-ConfluenceCurl -Method GET -Url 'https://x.atlassian.net/wiki/rest/api/content/1' -Email 'a@b.c' -ApiToken 'SECRET' } |
            Should -Not -Throw
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
