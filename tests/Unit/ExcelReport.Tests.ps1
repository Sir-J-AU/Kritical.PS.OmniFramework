#requires -Modules Pester
BeforeDiscovery {
    $HasIX = [bool](Get-Module -ListAvailable -Name ImportExcel)
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
    $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("krit-omni-xl-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:Tmp | Out-Null
}
AfterAll {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'New-KriticalExcelReport (requires ImportExcel)' {
    It 'writes a multi-sheet xlsx including the Kritical banner sheet' -Skip:(-not $HasIX) {
        $out  = Join-Path $script:Tmp 'rpt.xlsx'
        $data = @(
            [pscustomobject]@{ Name = 'pwsh'; Present = $true  }
            [pscustomobject]@{ Name = 'nope'; Present = $false }
        )
        $other = @([pscustomobject]@{ Key='alpha'; Value=1 })
        $r = New-KriticalExcelReport -Title 'UnitTest' -Sheet @{ Tools = $data; Misc = $other } -OutFile $out
        Test-Path -LiteralPath $out | Should -BeTrue
        $r.Sheets | Should -Be 3   # Kritical + Tools + Misc
        $r.Renderer | Should -Be 'ImportExcel'
        # Open and inspect sheet names
        $names = (Get-ExcelSheetInfo -Path $out).Name | Sort-Object
        $names | Should -Contain 'Kritical'
        $names | Should -Contain 'Tools'
        $names | Should -Contain 'Misc'
    }
    It 'auto-creates the parent directory when OutFile parent does not exist' -Skip:(-not $HasIX) {
        $deep = Join-Path $script:Tmp ("missing-" + [guid]::NewGuid() + "\sub\rpt.xlsx")
        { New-KriticalExcelReport -Title 'UnitTest' -Sheet @{ T = @([pscustomobject]@{a=1}) } -OutFile $deep } | Should -Not -Throw
        Test-Path -LiteralPath $deep | Should -BeTrue
    }
    It 'throws cleanly when ImportExcel is not installed' -Skip:($HasIX) {
        { New-KriticalExcelReport -Title 'UnitTest' -Sheet @{ T = @() } -OutFile (Join-Path $script:Tmp 'x.xlsx') } | Should -Throw -ExpectedMessage '*ImportExcel*'
    }
}
