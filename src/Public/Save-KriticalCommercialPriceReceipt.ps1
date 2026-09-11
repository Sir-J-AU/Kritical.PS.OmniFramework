function Save-KriticalCommercialPriceReceipt {
    <#
    .SYNOPSIS
        Writes a redacted, hash-pinned supplier-price query receipt.

    .DESCRIPTION
        Accepts evidence from Pax8, Dicker or Crayon only. Secret-bearing keys are
        rejected rather than redacted silently. The receipt captures query shape,
        selected response rows, quantity/term/currency/tax basis and timestamps,
        but never credentials, bearer tokens or raw HTTP headers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Pax8','Dicker','Crayon')] [string]$Vendor,
        [Parameter(Mandatory)] [hashtable]$Query,
        [Parameter(Mandatory)] [object[]]$Rows,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Z]{3}$')] [string]$Currency,
        [Parameter(Mandatory)] [ValidateSet('ex-GST','inc-GST','GST-free','vendor-unknown')] [string]$TaxBasis,
        [Parameter(Mandatory)] [ValidateRange(1, 1000000)] [int]$Quantity,
        [Parameter(Mandatory)] [string]$BillingTerm,
        [Parameter(Mandatory)] [string]$CommitmentTerm,
        [Parameter(Mandatory)] [string]$OutputDirectory
    )

    $forbidden = 'token|secret|password|authorization|cookie|credential|api[_-]?key'
    function Assert-SafeValue([object]$Value, [string]$Path = 'root') {
        if ($null -eq $Value) { return }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                if ([string]$key -match $forbidden) { throw "Commercial receipt rejects secret-bearing field '$Path.$key'." }
                Assert-SafeValue -Value $Value[$key] -Path "$Path.$key"
            }
        } elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            foreach ($item in $Value) { Assert-SafeValue -Value $item -Path "$Path[]" }
        } elseif ($Value -is [psobject] -and -not ($Value -is [string])) {
            foreach ($property in $Value.PSObject.Properties) {
                if ($property.Name -match $forbidden) { throw "Commercial receipt rejects secret-bearing field '$Path.$($property.Name)'." }
                Assert-SafeValue -Value $property.Value -Path "$Path.$($property.Name)"
            }
        }
    }
    Assert-SafeValue $Query
    Assert-SafeValue $Rows

    $capturedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $queryJson = $Query | ConvertTo-Json -Depth 20 -Compress
    $rowsJson = @($Rows) | ConvertTo-Json -Depth 20 -Compress
    $querySha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($queryJson))).ToLowerInvariant()
    $rowsSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($rowsJson))).ToLowerInvariant()
    $receipt = [ordered]@{
        receiptId = "commercial-price-$($Vendor.ToLowerInvariant())-$([guid]::NewGuid().ToString('N'))"
        capturedUtc = $capturedUtc
        vendor = $Vendor
        query = $Query
        querySha256 = $querySha
        selectedRows = @($Rows)
        selectedRowsSha256 = $rowsSha
        quantity = $Quantity
        billingTerm = $BillingTerm
        commitmentTerm = $CommitmentTerm
        currency = $Currency
        taxBasis = $TaxBasis
        secretPolicy = 'No credential, token, header, cookie or API-key field is admitted.'
    }
    $target = [IO.Path]::GetFullPath($OutputDirectory)
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $path = Join-Path $target ("price-query-$($Vendor.ToLowerInvariant())-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ'))-$([guid]::NewGuid().ToString('N')).json")
    $receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8NoBOM -NoNewline
    [pscustomobject]@{ Path=$path; Receipt=$receipt; Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
}
