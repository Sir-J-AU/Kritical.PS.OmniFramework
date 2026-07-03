#requires -Modules Pester
# Author: Joshua Finley - Kritical Pty Ltd
# Locks the brand + author stamp + the exported-function inventory so a future
# refactor cannot quietly drop a public surface without the test screaming.

BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $script:Psd1     = Join-Path $script:RepoRoot 'src\Kritical.PS.OmniFramework.psd1'
    Import-Module (Join-Path $script:RepoRoot 'src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'Manifest integrity' {
    It 'Test-ModuleManifest passes' {
        $mi = Test-ModuleManifest -Path $script:Psd1
        $mi | Should -Not -BeNullOrEmpty
        $mi.Name        | Should -Be 'Kritical.PS.OmniFramework'
        $mi.Author      | Should -Be 'Joshua Finley'
        $mi.CompanyName | Should -Be 'Kritical Pty Ltd'
        $mi.Copyright   | Should -Match 'Kritical'
    }
    It 'Every FunctionsToExport entry actually exists in the loaded module' {
        $mi = Test-ModuleManifest -Path $script:Psd1
        $exported = (Get-Command -Module Kritical.PS.OmniFramework | Select-Object -ExpandProperty Name) | Sort-Object
        foreach ($f in $mi.ExportedFunctions.Keys) {
            $exported | Should -Contain $f -Because "manifest declares $f but the module did not export it"
        }
    }
    It 'No AI-agent name leaks into manifest tags / description / release notes' {
        $raw = Get-Content -LiteralPath $script:Psd1 -Raw
        foreach ($bad in 'Claude','Hermes','Codex','Copilot','ChatGPT','Anthropic','OpenAI') {
            $raw | Should -Not -Match $bad -Because "manifest must not reference AI-agent name $bad"
        }
    }
}

Describe 'Banner asset bundled' {
    It 'src/Assets/kritical-logo.txt exists and contains the canonical SirJ banner' {
        $asset = Join-Path $script:RepoRoot 'src/Assets/kritical-logo.txt'
        Test-Path -LiteralPath $asset | Should -BeTrue
        $body = Get-Content -LiteralPath $asset -Raw
        $body | Should -Match 'SirJ'
        $body | Should -Match 'Kritical'
        $body | Should -Match '1300 274 655'
    }
}

Describe 'No AI-agent strings in any published source file' {
    It 'no src/**/*.ps1 or *.psm1 mentions Claude/Hermes/Codex/Copilot/ChatGPT/Anthropic/OpenAI' {
        $srcDir = Join-Path $script:RepoRoot 'src'
        $files = Get-ChildItem -LiteralPath $srcDir -Recurse -File -Include *.ps1,*.psm1,*.psd1
        $bad = foreach ($f in $files) {
            $c = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($c -and $c -match '(?i)\b(Claude|Hermes|Codex|Copilot|ChatGPT|Anthropic|OpenAI)\b') {
                [pscustomobject]@{ File = $f.FullName; Match = $matches[1] }
            }
        }
        $bad | Should -BeNullOrEmpty -Because ("found AI-agent names in: " + (($bad | ForEach-Object { $_.File }) -join ', '))
    }
}
