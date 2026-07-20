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

Describe 'Write-KriticalBanner agentic suppression' {
    BeforeEach {
        $script:savedEnv = @{
            CLAUDECODE = $env:CLAUDECODE; AI_AGENT = $env:AI_AGENT
            KRIT_NO_BANNER = $env:KRIT_NO_BANNER; CURSOR_TRACE_ID = $env:CURSOR_TRACE_ID
            COPILOT_AGENT = $env:COPILOT_AGENT
        }
        $env:CLAUDECODE = $null; $env:AI_AGENT = $null
        $env:KRIT_NO_BANNER = $null; $env:CURSOR_TRACE_ID = $null; $env:COPILOT_AGENT = $null
    }
    AfterEach {
        $env:CLAUDECODE = $script:savedEnv.CLAUDECODE; $env:AI_AGENT = $script:savedEnv.AI_AGENT
        $env:KRIT_NO_BANNER = $script:savedEnv.KRIT_NO_BANNER
        $env:CURSOR_TRACE_ID = $script:savedEnv.CURSOR_TRACE_ID; $env:COPILOT_AGENT = $script:savedEnv.COPILOT_AGENT
    }

    It 'prints when no agentic marker is set' {
        Test-KriticalAgenticSession | Should -Be $false
        (Write-KriticalBanner -Compact -NoColor 6>&1 *>&1 | Out-String) | Should -Match 'Kritical'
    }
    It 'suppresses under $env:CLAUDECODE' {
        $env:CLAUDECODE = '1'
        Test-KriticalAgenticSession | Should -Be $true
        (Write-KriticalBanner -Compact -NoColor *>&1 | Out-String) | Should -BeNullOrEmpty
    }
    It 'suppresses under $env:AI_AGENT' {
        $env:AI_AGENT = 'claude-code_2-1-215_agent'
        Test-KriticalAgenticSession | Should -Be $true
        (Write-KriticalBanner -Compact -NoColor *>&1 | Out-String) | Should -BeNullOrEmpty
    }
    It 'suppresses under explicit $env:KRIT_NO_BANNER opt-out' {
        $env:KRIT_NO_BANNER = '1'
        Test-KriticalAgenticSession | Should -Be $true
        (Write-KriticalBanner -Compact -NoColor *>&1 | Out-String) | Should -BeNullOrEmpty
    }
    It '-Force overrides agentic suppression' {
        $env:CLAUDECODE = '1'
        (Write-KriticalBanner -Compact -NoColor -Force *>&1 | Out-String) | Should -Match 'Kritical'
    }
}
