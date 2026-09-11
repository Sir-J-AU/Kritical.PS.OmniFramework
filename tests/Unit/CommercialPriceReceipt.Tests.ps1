BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $root 'src\Kritical.PS.OmniFramework.psd1') -Force
    $script:Out = Join-Path $env:TEMP ('krit-price-receipt-' + [guid]::NewGuid().ToString('N'))
}
AfterAll { Remove-Item -LiteralPath $script:Out -Recurse -Force -ErrorAction SilentlyContinue }
Describe 'commercial price receipt' {
    It 'writes a hash-pinned receipt without credentials' {
        $result = Save-KriticalCommercialPriceReceipt -Vendor Pax8 -Query @{search='NinjaOne'; productId='4b361c53-ab3b-449a-8629-6ad350d1fae5'} -Rows @([pscustomobject]@{sku='DRP-BUP-BBU-C100'; partnerBuyRate=36.28044}) -Currency AUD -TaxBasis ex-GST -Quantity 7 -BillingTerm Annual -CommitmentTerm 1-Year -OutputDirectory $script:Out
        $result.Path | Should -Exist
        $result.Receipt.vendor | Should -Be 'Pax8'
        $result.Receipt.querySha256 | Should -Match '^[0-9a-f]{64}$'
        $result.Receipt.selectedRowsSha256 | Should -Match '^[0-9a-f]{64}$'
    }
    It 'refuses token-bearing evidence instead of persisting it' {
        { Save-KriticalCommercialPriceReceipt -Vendor Pax8 -Query @{authorization='Bearer never-store'} -Rows @([pscustomobject]@{sku='x'}) -Currency AUD -TaxBasis ex-GST -Quantity 1 -BillingTerm Monthly -CommitmentTerm None -OutputDirectory $script:Out } | Should -Throw '*secret-bearing*'
    }
}
