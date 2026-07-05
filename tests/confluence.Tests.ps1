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
