#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
    $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-omni-sec-" + [guid]::NewGuid())
    $script:Sec = Join-Path $script:Tmp 'secrets'
    New-Item -ItemType Directory -Path $script:Sec -Force | Out-Null
    'mock' | Set-Content -LiteralPath (Join-Path $script:Sec 'present.txt')
}
AfterAll {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-KriticalSecretsLoaded' {
    It 'reports Ok=$true when folder exists and no files required' {
        $r = Test-KriticalSecretsLoaded -SecretsDir $script:Sec
        $r.SecretsDir    | Should -Be $script:Sec
        $r.FolderPresent | Should -BeTrue
        $r.MissingFiles  | Should -BeNullOrEmpty
        $r.Ok            | Should -BeTrue
    }
    It 'reports Ok=$true when every required file is present' {
        $r = Test-KriticalSecretsLoaded -SecretsDir $script:Sec -RequireFiles 'present.txt'
        $r.Ok           | Should -BeTrue
        $r.MissingFiles | Should -BeNullOrEmpty
    }
    It 'reports Ok=$false and lists missing files' {
        $r = Test-KriticalSecretsLoaded -SecretsDir $script:Sec -RequireFiles 'present.txt','absent.txt'
        $r.Ok           | Should -BeFalse
        $r.MissingFiles | Should -Contain 'absent.txt'
    }
    It 'reports Ok=$false when secrets folder itself is missing' {
        $bogus = Join-Path $script:Tmp 'does-not-exist'
        $r = Test-KriticalSecretsLoaded -SecretsDir $bogus
        $r.FolderPresent | Should -BeFalse
        $r.Ok            | Should -BeFalse
    }
}
