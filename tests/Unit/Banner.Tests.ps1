#requires -Modules Pester
# Author: Joshua Finley - Kritical Pty Ltd

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psd1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    # Manifest may fail strict module checks until RequiredModules are installed; fall back to .psm1
    if (-not (Get-Module Kritical.PS.OmniFramework)) {
        Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
    }
}

Describe 'Get-KriticalBanner' {
    It 'returns the canonical SirJ-deaddrop banner when present' {
        $b = Get-KriticalBanner
        $b | Should -Match 'SirJ'
        $b | Should -Match 'Kritical'
        $b | Should -Match '1300 274 655'
    }

    It '-Compact returns one-line summary' {
        $b = Get-KriticalBanner -Compact
        $b | Should -Match 'Kritical'
        @(($b -split "`r?`n") | Where-Object { $_ }).Count | Should -BeLessOrEqual 1
    }

    It '-Title appends a title block when not Compact' {
        (Get-KriticalBanner -Title 'UnitTest') | Should -Match '--- UnitTest ---'
    }

    It 'falls back gracefully when LogoPath does not exist' {
        $b = Get-KriticalBanner -LogoPath 'X:\nope\does\not\exist.txt'
        $b | Should -Match 'Kritical'
    }
}

Describe 'Write-KriticalBanner' {
    It 'does not throw (full)'    { { Write-KriticalBanner -Title 'Unit' -NoColor } | Should -Not -Throw }
    It 'does not throw (compact)' { { Write-KriticalBanner -Compact -NoColor } | Should -Not -Throw }
}
