#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'Get-KriticalToolInventory' {
    It 'returns rows for a small custom list' {
        $tools = Get-KriticalToolInventory -Tool 'pwsh','definitely-not-installed-xyz123'
        $tools.Count | Should -Be 2
        ($tools | Where-Object Name -eq 'pwsh').Present                        | Should -BeTrue
        ($tools | Where-Object Name -eq 'definitely-not-installed-xyz123').Present | Should -BeFalse
    }
    It 'sets FirstPath on a present tool' {
        $row = (Get-KriticalToolInventory -Tool 'pwsh') | Select-Object -First 1
        $row.FirstPath | Should -Not -BeNullOrEmpty
        $row.HitCount  | Should -BeGreaterOrEqual 1
    }
    It 'returns multiple rows when called with no -Tool (uses canonical list)' {
        $all = Get-KriticalToolInventory
        $all.Count | Should -BeGreaterThan 10
    }
}

Describe 'Find-KriticalTool / Test-KriticalToolPresent' {
    It 'Find-KriticalTool returns at least one match for pwsh on this machine' {
        $hits = Find-KriticalTool -Name pwsh
        $hits.Count | Should -BeGreaterOrEqual 1
        ($hits | Select-Object -First 1).Path | Should -Not -BeNullOrEmpty
    }
    It 'Test-KriticalToolPresent agrees' {
        Test-KriticalToolPresent -Name pwsh | Should -BeTrue
        Test-KriticalToolPresent -Name 'definitely-not-installed-xyz123' | Should -BeFalse
    }
}
