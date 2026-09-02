#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
    # Build a fake repo: <tmp>/repo/{ .git/HEAD, krit-project.json, subdir/inner }
    $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-omni-cfg-" + [guid]::NewGuid())
    $script:Repo = Join-Path $script:Tmp 'repo'
    New-Item -ItemType Directory -Path (Join-Path $script:Repo '.git') -Force | Out-Null
    'ref: refs/heads/main' | Set-Content -LiteralPath (Join-Path $script:Repo '.git\HEAD')
    @{
        projects = @{
            sample = @{ description = 'sample project'; idRange = '50100-50299' }
            other  = @{ description = 'other project' }
        }
        paths = @{
            output = 'out/generated'
            absroot = 'C:\absolute\path'
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:Repo 'krit-project.json')
    New-Item -ItemType Directory -Path (Join-Path $script:Repo 'subdir/inner') -Force | Out-Null
}
AfterAll {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-KriticalRepoRoot' {
    It 'finds the repo root from a nested subdir' {
        $r = Resolve-KriticalRepoRoot -StartPath (Join-Path $script:Repo 'subdir/inner')
        $r | Should -Be (Resolve-Path -LiteralPath $script:Repo).Path
    }
    It 'returns the repo path when called at the root' {
        $r = Resolve-KriticalRepoRoot -StartPath $script:Repo
        $r | Should -Be (Resolve-Path -LiteralPath $script:Repo).Path
    }
    It 'returns $null when no marker is found above the start path' {
        $orphan = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-omni-orphan-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $orphan -Force | Out-Null
        try {
            $r = Resolve-KriticalRepoRoot -StartPath $orphan
            $r | Should -BeNullOrEmpty
        } finally {
            Remove-Item -LiteralPath $orphan -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-KriticalConfig' {
    It 'loads krit-project.json from the resolved root' {
        $c = Get-KriticalConfig -StartPath (Join-Path $script:Repo 'subdir/inner')
        $c.RepoRoot   | Should -Be (Resolve-Path -LiteralPath $script:Repo).Path
        $c.ConfigName | Should -Be 'krit-project.json'
        $c.Config     | Should -Not -BeNullOrEmpty
        $c.Config.projects.sample.idRange | Should -Be '50100-50299'
    }

    It 'returns Config null with a warning when the discovered JSON is malformed' {
        $badRepo = Join-Path $script:Tmp 'bad-repo'
        New-Item -ItemType Directory -Path (Join-Path $badRepo '.git') -Force | Out-Null
        'ref: refs/heads/main' | Set-Content -LiteralPath (Join-Path $badRepo '.git\HEAD')
        '{ malformed-json' | Set-Content -LiteralPath (Join-Path $badRepo 'krit-project.json') -Encoding utf8
        $warnings = @()
        $c = Get-KriticalConfig -StartPath $badRepo -WarningVariable warnings -WarningAction Continue
        $c.ConfigName | Should -Be 'krit-project.json'
        $c.Config | Should -BeNullOrEmpty
        ($warnings -join "`n") | Should -Match 'is not valid JSON'
        ($warnings -join "`n") | Should -Match 'krit-project\.json'
    }
}

Describe 'Get-KriticalProject' {
    It 'returns the named project node' {
        $p = Get-KriticalProject -StartPath $script:Repo -Name sample
        $p.idRange | Should -Be '50100-50299'
    }
    It 'returns $null for an unknown project' {
        $p = Get-KriticalProject -StartPath $script:Repo -Name nope
        $p | Should -BeNullOrEmpty
    }
}

Describe 'Get-KriticalPath' {
    It 'resolves a relative path against the repo root' {
        $p = Get-KriticalPath -StartPath $script:Repo -Name output
        $p | Should -Be (Join-Path (Resolve-Path -LiteralPath $script:Repo).Path 'out/generated')
    }
    It 'preserves an absolute path verbatim' {
        $p = Get-KriticalPath -StartPath $script:Repo -Name absroot
        $p | Should -Be 'C:\absolute\path'
    }
    It 'returns $null for an unknown path name' {
        (Get-KriticalPath -StartPath $script:Repo -Name nope) | Should -BeNullOrEmpty
    }
}
