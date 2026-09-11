function Get-KriticalAuthorityTuple {
    <#
    .SYNOPSIS
        Obtains one redacted effective configuration tuple through GreatWhite ES.

    .DESCRIPTION
        This is the only supported client-side path to AllEnvironmentDetails. It calls the
        read-only get_effective_authority_tuple MCP tool and returns policy metadata plus secret
        reference names only. It never connects directly to SQL and never returns a secret value.
        An unavailable/not-checked authority is a terminating error by design: callers must not
        silently substitute a local configuration as if it were authoritative.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pax8','d365bc','environment-switcher','document-renderer')]
        [string] $Consumer,

        [Parameter(Mandatory)]
        [ValidateSet('dev','test','prod')]
        [string] $Environment,

        [string] $BaseUri = $env:KRIT_GW_MCP_BASE_URI,
        [string] $BearerToken = $env:GW_MCP_BEARER_TOKEN
    )

    if ([string]::IsNullOrWhiteSpace($BaseUri)) {
        throw 'ES authority endpoint is unavailable. Set KRIT_GW_MCP_BASE_URI; direct SQL fallback is refused.'
    }
    if ([string]::IsNullOrWhiteSpace($BearerToken)) {
        throw 'ES authority bearer reference is unavailable. Set GW_MCP_BEARER_TOKEN; unauthenticated authority access is refused.'
    }

    $body = @{
        jsonrpc = '2.0'
        id = 1
        method = 'tools/call'
        params = @{ name = 'get_effective_authority_tuple'; arguments = @{ consumer = $Consumer; environment = $Environment } }
    } | ConvertTo-Json -Depth 8 -Compress

    try {
        $response = Invoke-RestMethod -Uri $BaseUri -Method Post -ContentType 'application/json' -Headers @{ Authorization = "Bearer $BearerToken" } -Body $body -ErrorAction Stop
    }
    catch {
        throw "ES authority request failed: $($_.Exception.Message)"
    }
    if ($response.PSObject.Properties['error']) {
        throw "ES authority request was refused: $($response.error.message)"
    }
    $textBlock = @($response.result.content) | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
    if (-not $textBlock -or [string]::IsNullOrWhiteSpace([string]$textBlock.text)) {
        throw 'ES authority response has no MCP text payload.'
    }
    try { $tuple = $textBlock.text | ConvertFrom-Json -Depth 16 -ErrorAction Stop }
    catch { throw "ES authority response is not valid JSON: $($_.Exception.Message)" }

    if ($tuple.status -ne 'ok') {
        throw "ES authority returned status '$($tuple.status)' instead of ok: $($tuple.reason)"
    }
    if ($tuple.consumer -ne $Consumer -or $tuple.environment -ne $Environment) {
        throw 'ES authority response consumer/environment does not match the requested tuple.'
    }
    if ($null -eq $tuple.rows -or -not ($tuple.rows -is [System.Collections.IEnumerable])) {
        throw 'ES authority response rows are missing or malformed.'
    }

    $prefix = "client.$Consumer.$Environment."
    foreach ($row in @($tuple.rows)) {
        if ([string]::IsNullOrWhiteSpace($row.policy_key) -or -not $row.policy_key.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            throw 'ES authority response contains a policy key outside the requested consumer/environment scope.'
        }
        if ($row.value_kind -notin @('env-var-name','filesystem-path','port','string','utc-datetime')) {
            throw 'ES authority response has an unsupported policy value kind.'
        }
        $keyLooksSecret = $row.policy_key -match '(?i)(secret|password|token|connection)'
        if ($keyLooksSecret -and $row.value_kind -ne 'env-var-name') {
            throw 'ES authority response contains a secret-like value instead of a secret-reference name.'
        }
        if ($row.value_kind -eq 'env-var-name' -and [string]$row.value_text -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,199}$') {
            throw 'ES authority response has an invalid environment-variable reference name.'
        }
    }
    $tuple
}
