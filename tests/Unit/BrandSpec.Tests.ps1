$here = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
$module = Join-Path $repoRoot 'src\Kritical.PS.OmniFramework.psd1'
Import-Module $module -Force

Describe 'Get-KriticalBrandSpec' {
    BeforeAll {
        $script:Spec = Get-KriticalBrandSpec -Refresh
    }

    It 'returns a non-null brand spec' {
        $Spec | Should -Not -BeNullOrEmpty
    }

    It 'has entity / contact / messaging / colours / typography sections' {
        $Spec.entity     | Should -Not -BeNullOrEmpty
        $Spec.contact    | Should -Not -BeNullOrEmpty
        $Spec.messaging  | Should -Not -BeNullOrEmpty
        $Spec.colours    | Should -Not -BeNullOrEmpty
        $Spec.typography | Should -Not -BeNullOrEmpty
    }

    It 'has canonical Kritical dark blue primary colour' {
        $Spec.colours.primary.kriticalDarkBlue | Should -Be '#13365C'
    }

    It 'has canonical ABN + ACN' {
        $Spec.entity.abn | Should -Be '39 687 048 086'
        $Spec.entity.acn | Should -Be '687 048 086'
    }

    It 'has canonical tagline' {
        $Spec.messaging.tagline | Should -Be 'Your last call. And your first move.'
    }

    It 'caches across calls (second call returns same object identity OR equivalent content)' {
        $first  = Get-KriticalBrandSpec
        $second = Get-KriticalBrandSpec
        $second.entity.abn | Should -Be $first.entity.abn
    }
}

Describe 'New-KriticalBrandedDocument (smoke - requires Pandoc)' {
    BeforeDiscovery {
        $script:HasPandoc = $null -ne (Get-Command pandoc -ErrorAction SilentlyContinue)
    }

    It 'renders a simple .md to HTML when Pandoc is installed' -Skip:(-not $script:HasPandoc) {
        $tmp = Join-Path $env:TEMP ("krit-omni-test-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $src = Join-Path $tmp 'sample.md'
        @"
# Sample Document

This is a test paragraph with **bold** and *italic*.

| Col1 | Col2 |
|---|---|
| A | B |

> A blockquote.
"@ | Set-Content -LiteralPath $src -Encoding UTF8

        $result = New-KriticalBrandedDocument -Source $src -OutDir $tmp -Format HTML `
            -CustomerName 'TestCo' -DocumentTitle 'Smoke' -NoBanner

        $result | Should -Not -BeNullOrEmpty
        $result.Outputs.Count | Should -BeGreaterThan 0
        $htmlOutput = $result.Outputs | Where-Object Format -eq 'HTML' | Select-Object -First 1
        $htmlOutput.Path | Should -Exist
        $content = Get-Content -LiteralPath $htmlOutput.Path -Raw
        $content | Should -Match '#13365C'         # primary colour applied
        $content | Should -Match 'Sample Document' # body content rendered
        $content | Should -Match 'ABN 39 687 048 086' # footer applied

        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
