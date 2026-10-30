#Requires -Version 7
<#
.SYNOPSIS
    Krit.FixtureApi — Auto-generated from OpenAPI 1.0.0 by Lens-OpenApiToPsModule-1507.mjs
.DESCRIPTION
    Fixture vendor (binding-layer tests only)
    Generator wave: .1507o7
.NOTES
    Author: Joshua Finley (Kritical Pty Ltd)
    Base URI: https://fixture.example.test
    Auth: bearer
#>

$script:DefaultFixtureBaseUri = 'https://fixture.example.test'

# ─── OmniFramework foundation (soft-load, 1.0.2 resilience pattern) ──────────
function Import-KritFixtureOmniSoft {
    # Soft-import Kritical.PS.OmniFramework. Never hard-fail at import even when
    # Omni is missing or AppDomain-locked at an older version — declared via
    # ExternalModuleDependencies (NOT RequiredModules) so a stale PSFramework
    # AppDomain lock cannot cascade into an Import-Module failure.
    [CmdletBinding()]
    param([switch]$Quiet)
    $already = Get-Module -Name Kritical.PS.OmniFramework -ErrorAction SilentlyContinue
    if ($already) { return @{ Ok = $true; Version = $already.Version; Source = 'already-loaded' } }
    $have = Get-Module -ListAvailable -Name Kritical.PS.OmniFramework -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
    if (-not $have) { return @{ Ok = $false; Version = $null; Source = 'not-installed' } }
    try {
        Import-Module -Name Kritical.PS.OmniFramework -ErrorAction Stop
        $loaded = Get-Module -Name Kritical.PS.OmniFramework | Select-Object -First 1
        return @{ Ok = $true; Version = $loaded.Version; Source = 'imported' }
    } catch {
        if (-not $Quiet.IsPresent) { Write-Warning ('Kritical.PS.OmniFramework soft-import failed: ' + $_.Exception.Message) }
        return @{ Ok = $false; Version = $have.Version; Source = 'import-failed'; Error = $_.Exception.Message }
    }
}
$script:KritFixtureOmniSoft = (Import-KritFixtureOmniSoft -Quiet)

function Write-KritFixtureLog {
    # Structured logger. Prefers OmniFramework's Write-KriticalLog (PSFramework-
    # backed) when the foundation is loaded; degrades to a local host/Verbose
    # fallback otherwise so a generated function never hard-depends on Omni.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug','Verbose','Info','Warning','Error','Critical')][string]$Level = 'Info',
        [string[]]$Tag,
        [hashtable]$Data
    )
    $omni = Get-Command -Name Write-KriticalLog -ErrorAction SilentlyContinue
    if ($omni) {
        try {
            $p = @{ Message = $Message; Level = $Level }
            if ($Tag)  { $p.Tag  = $Tag }
            if ($Data) { $p.Data = $Data }
            Write-KriticalLog @p
            return
        } catch { Write-Debug ('OmniFramework Write-KriticalLog failed; using local fallback: ' + $_.Exception.Message) }
    }
    switch ($Level) {
        'Error'    { Write-Host ('[' + $Level + '] ' + $Message) -ForegroundColor Red }
        'Critical' { Write-Host ('[' + $Level + '] ' + $Message) -ForegroundColor Red }
        'Warning'  { Write-Host ('[' + $Level + '] ' + $Message) -ForegroundColor Yellow }
        'Verbose'  { Write-Verbose $Message }
        'Debug'    { Write-Debug   $Message }
        default    { Write-Host ('[' + $Level + '] ' + $Message) -ForegroundColor Gray }
    }
}

function Get-KritFixtureBanner {
    # 3-tier brand-banner resolution: secrets folder > canonical branding > none.
    [CmdletBinding()]
    param()
    $candidates = @(
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\KriticalLogo.txt'),
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Kritical-Branding\public\KriticalLogo.txt')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            try { return (Get-Content -LiteralPath $c -Raw) } catch { Write-Debug ('Banner read failed: ' + $_.Exception.Message) }
        }
    }
    return $null
}

function Write-KritFixtureBanner {
    [CmdletBinding()]
    param([switch]$Compact)
    if ($env:KRIT_NO_BANNER) { return }
    $logo = Get-KritFixtureBanner
    if ($logo -and -not $Compact.IsPresent) { Write-Host $logo -ForegroundColor DarkCyan }
    Write-Host '--- Krit.FixtureOpenApi (OmniFramework-enhanced client) ---' -ForegroundColor Yellow
}

if (-not $env:KRIT_NO_BANNER) { Write-KritFixtureBanner -Compact }
Write-KritFixtureLog -Level Verbose -Message 'Krit.FixtureOpenApi module loaded' -Tag 'krit-openapi','fixture' -Data @{ omni = $script:KritFixtureOmniSoft.Source }

$script:KritFixtureBaseUriProvider = $null

function Set-KritFixtureBaseUriProvider {
    <# Install a caller-owned base-URI provider. HTTPS is required except for HTTP loopback development. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][scriptblock]$Provider)
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Set base-URI provider')) {
        $script:KritFixtureBaseUriProvider = $Provider
    }
}

function Get-KritFixtureBaseUriProvider {
    [CmdletBinding()]
    param()
    return $script:KritFixtureBaseUriProvider
}

function Clear-KritFixtureBaseUriProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Clear base-URI provider')) {
        $script:KritFixtureBaseUriProvider = $null
    }
}

function Get-KritFixtureBaseUri {
    if ($script:KritFixtureBaseUriProvider) {
        $providedBaseUri = & $script:KritFixtureBaseUriProvider
        $parsedBaseUri = $null
        if ($providedBaseUri -isnot [string] -or [string]::IsNullOrWhiteSpace($providedBaseUri) -or
            -not [uri]::TryCreate($providedBaseUri, [UriKind]::Absolute, [ref]$parsedBaseUri) -or
            ($parsedBaseUri.Scheme -ne 'https' -and -not ($parsedBaseUri.Scheme -eq 'http' -and $parsedBaseUri.IsLoopback))) {
            throw 'Base-URI provider must return an absolute HTTPS URI, or HTTP loopback for development.'
        }
        return $providedBaseUri.TrimEnd('/')
    }
    $value = if ($env:KRIT_FIXTURE_BASE_URI) { $env:KRIT_FIXTURE_BASE_URI } else { $script:DefaultFixtureBaseUri }
    return $value.TrimEnd('/')
}

$script:KritFixtureTokenProvider = $null

function Set-KritFixtureTokenProvider {
    <#
    .SYNOPSIS
        Install a dynamic bearer-token provider for this generated client.
    .DESCRIPTION
        The provider is invoked once per request and must return one non-empty token string.
        It owns acquisition, refresh and caching; this module never logs or persists the value.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][scriptblock]$Provider)
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Set token provider')) {
        $script:KritFixtureTokenProvider = $Provider
    }
}

function Get-KritFixtureTokenProvider {
    [CmdletBinding()]
    param()
    return $script:KritFixtureTokenProvider
}

function Clear-KritFixtureTokenProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Clear token provider')) {
        $script:KritFixtureTokenProvider = $null
    }
}

function Get-KritFixtureToken {
    # USER/CONTEXT DOCUMENTATION - NOT GENERATED BY LENS: dynamic providers are the
    # supported seam for OAuth libraries, CLIs and vault-backed refresh workflows.
    if ($script:KritFixtureTokenProvider) {
        $providedToken = & $script:KritFixtureTokenProvider
        if ($providedToken -isnot [string] -or [string]::IsNullOrWhiteSpace($providedToken)) {
            throw 'Token provider must return a non-empty string.'
        }
        return $providedToken
    }
    # Backward-compatible static token source (env name is --TokenEnv, default KRIT_<BRAND>_TOKEN).
    if ($env:KRIT_FIXTURE_TOKEN) {
        $environmentToken = [string]$env:KRIT_FIXTURE_TOKEN
        if (-not [string]::IsNullOrWhiteSpace($environmentToken)) { return $environmentToken }
    }
    # Fallback to secret file convention .908
    $secretsDir = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos'
    if (Test-Path $secretsDir) {
        $tokenFile = Get-ChildItem -Path $secretsDir -Filter 'kritical-fixture-*-token-*.txt' |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($tokenFile) {
            $fileToken = (Get-Content -LiteralPath $tokenFile.FullName -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($fileToken)) { return $fileToken }
        }
    }
    throw 'No Fixture token. Set $env:KRIT_FIXTURE_TOKEN or place a matching token file in ' + $secretsDir
}

$script:KritFixtureRequestHook = $null

$script:KritFixtureTransportProvider = $null

function Set-KritFixtureTransportProvider {
    <#
    .SYNOPSIS
        Install a caller-owned HTTP transport provider for this generated client.
    .DESCRIPTION
        The provider receives the final request hashtable immediately before transport and
        returns the deserialised response. It is intended for governed host transports and
        disposable offline fixtures; this module never persists, logs or inspects credentials
        carried in the request headers.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][scriptblock]$Provider)
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Set transport provider')) {
        $script:KritFixtureTransportProvider = $Provider
    }
}

function Get-KritFixtureTransportProvider {
    [CmdletBinding()]
    param()
    return $script:KritFixtureTransportProvider
}

function Clear-KritFixtureTransportProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Clear transport provider')) {
        $script:KritFixtureTransportProvider = $null
    }
}

function Set-KritFixtureRequestHook {
    <#
    .SYNOPSIS
        Install the supported per-request extension point for non-standard authentication.
    .DESCRIPTION
        The hook runs after URI, headers and body are assembled but before body serialization
        and transport. It receives an ordered IDictionary with Method, Path, Uri, Headers,
        Body, ContentType and Form. Mutate it in place and return nothing, or return a complete
        replacement IDictionary. Never log or persist credential values from the context.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][AllowNull()][scriptblock]$Hook)
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Set request hook')) {
        $script:KritFixtureRequestHook = $Hook
    }
}

function Get-KritFixtureRequestHook {
    [CmdletBinding()]
    param()
    return $script:KritFixtureRequestHook
}

function Clear-KritFixtureRequestHook {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Krit.FixtureOpenApi', 'Clear request hook')) {
        $script:KritFixtureRequestHook = $null
    }
}

function Invoke-KritFixtureApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE','PATCH','HEAD')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$ContentType = 'application/json',
        # GATE FIX (2026-08-08, Swagger 2.0): multipart/form-data passthrough for "formData"
        # (file-upload) operations - see Lens-OpenApiToPsModule-1507.mjs emitFunction() for why.
        [hashtable]$Form,
        [hashtable]$Headers,
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3,
        [switch]$AllowMutationRetry
    )
    $uri = (Get-KritFixtureBaseUri) + $Path
    $requestHeaders = @{
        Authorization = "Bearer $(Get-KritFixtureToken)"
    }
    if ($Headers) {
        foreach ($key in $Headers.Keys) {
            $requestHeaders[$key] = $Headers[$key]
        }
    }
    $requestContext = [ordered]@{
        Method      = $Method
        Path        = $Path
        Uri         = $uri
        Headers     = $requestHeaders
        Body        = $Body
        ContentType = $ContentType
        Form        = $Form
    }
    if ($script:KritFixtureRequestHook) {
        $hookResult = & $script:KritFixtureRequestHook $requestContext
        if ($null -ne $hookResult) {
            if ($hookResult -isnot [System.Collections.IDictionary]) {
                throw 'Request hook must return an IDictionary or no value.'
            }
            $requestContext = $hookResult
        }
    }
    foreach ($requiredContextKey in @('Method','Path','Uri','Headers','Body','ContentType','Form')) {
        if (-not $requestContext.Contains($requiredContextKey)) {
            throw "Request hook context is missing required key '$requiredContextKey'."
        }
    }
    if ([string]$requestContext['Method'] -notin @('GET','POST','PUT','DELETE','PATCH','HEAD')) {
        throw "Request hook returned unsupported HTTP method '$($requestContext['Method'])'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$requestContext['Uri'])) {
        throw 'Request hook returned an empty Uri.'
    }
    if ($requestContext['Headers'] -isnot [System.Collections.IDictionary]) {
        throw 'Request hook Headers must be an IDictionary.'
    }

    $Body = $requestContext['Body']
    $ContentType = [string]$requestContext['ContentType']
    $Form = $requestContext['Form']
    $params = @{
        Method = [string]$requestContext['Method']
        Uri = [string]$requestContext['Uri']
        TimeoutSec = $TimeoutSec
        ErrorAction = 'Stop'
        Headers = $requestContext['Headers']
    }
    if ($Form) {
        # Invoke-RestMethod sets its own multipart/form-data Content-Type (with boundary) when
        # -Form is used - must not also set ContentType/Body, and JSON-body and multipart-form
        # are mutually exclusive per Swagger 2.0 anyway (an operation never declares both).
        $params.Form = $Form
    } else {
        $params.ContentType = $ContentType
        if ($null -ne $Body) {
            if ($ContentType -eq 'application/json') {
                # GATE FIX (2026-09-22): found live regenerating Kritical.PS.NetBox and re-running
                # its every-function Prism-mock proof - PowerShell's pipeline UNROLLS an array
                # before ConvertTo-Json ever sees it as a collection, so `$Body | ConvertTo-Json`
                # silently collapses a ONE-ITEM array body (e.g. -InputObject with a single
                # hashtable, an extremely common real case: bulk-updating/deleting just one
                # record) into a bare JSON object instead of a one-element JSON array, which a
                # spec-validating server correctly rejects ("Request body must be array"). A
                # multi-item array never showed the bug (2+ piped items are NOT unwrapped), which
                # is why it went unnoticed until a single-item bulk call was actually exercised.
                # -AsArray (PowerShell 6.2+) forces the top-level array shape regardless of the
                # piped item count; an explicit empty-array check covers the one shape -AsArray
                # itself cannot: piping zero items emits nothing at all, not even "[]".
                $params.Body = if ($Body -is [System.Array]) {
                    if ($Body.Count -eq 0) { '[]' } else { $Body | ConvertTo-Json -Depth 10 -Compress -AsArray }
                } else {
                    $Body | ConvertTo-Json -Depth 10 -Compress
                }
            }
            elseif ($ContentType -eq 'application/octet-stream') { $params.Body = [byte[]]$Body }
            else { $params.Body = [string]$Body }
        }
    }


    $attempt = 0
    while ($true) {
        try {
            if ($script:KritFixtureTransportProvider) {
                return & $script:KritFixtureTransportProvider $params
            }
            return Invoke-RestMethod @params
        } catch {
            $attempt++
            $retryAllowed = ([string]$params.Method) -in @('GET','HEAD') -or $AllowMutationRetry.IsPresent
            if (-not $retryAllowed) { throw }
            if ($attempt -ge $MaxRetries) { throw }
            $sleep = [Math]::Min(30, [Math]::Pow(2, $attempt))
            Write-Verbose "Retry $attempt/$MaxRetries after $sleep s: $($_.Exception.Message)"
            Start-Sleep -Seconds $sleep
        }
    }
}

function Invoke-KritFixtureApiPages {
    <#
    .SYNOPSIS
        Follow a caller-defined same-origin pagination chain and return a stable receipt.
    .DESCRIPTION
        Calls the generated transport with GET, then invokes GetNextPath with the response,
        current path and one-based page number. The resolver must return the next relative
        path, an absolute URI on the configured API origin, or null when complete. Cycles,
        cross-origin links, invalid resolver output and MaxPages truncation fail closed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$GetNextPath,
        [hashtable]$Headers,
        [int]$TimeoutSec = 30,
        [ValidateRange(1,10000)][int]$MaxPages = 100
    )

    $baseUri = [Uri](Get-KritFixtureBaseUri)
    $resolvePagePath = {
        param([object]$Candidate)
        if ($Candidate -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Candidate)) {
            throw 'Pagination path must be a non-empty string.'
        }
        $candidateText = [string]$Candidate
        $absolute = $null
        if ([Uri]::TryCreate($candidateText, [UriKind]::Absolute, [ref]$absolute)) {
            if ($absolute.Scheme -ne $baseUri.Scheme -or $absolute.Host -ne $baseUri.Host -or $absolute.Port -ne $baseUri.Port) {
                throw 'Pagination absolute URI must use the configured API same origin.'
            }
            return $absolute.PathAndQuery
        }
        if (-not $candidateText.StartsWith('/')) {
            throw 'Pagination path must start with / or be an absolute URI on the configured API origin.'
        }
        return $candidateText
    }

    $currentPath = & $resolvePagePath $Path
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $pages = [System.Collections.Generic.List[object]]::new()
    $paths = [System.Collections.Generic.List[string]]::new()
    $pageNumber = 0

    while ($true) {
        if (-not $visited.Add($currentPath)) {
            throw "Pagination cycle detected at path '$currentPath'."
        }
        $pageNumber++
        [void]$paths.Add($currentPath)
        $invokeParams = @{ Method = 'GET'; Path = $currentPath; TimeoutSec = $TimeoutSec }
        if ($Headers) { $invokeParams.Headers = $Headers }
        $response = Invoke-KritFixtureApi @invokeParams
        [void]$pages.Add($response)

        $nextPath = & $GetNextPath $response $currentPath $pageNumber
        if ($null -eq $nextPath) {
            return [pscustomobject]@{
                Count = $pages.Count
                Pages = $pages.ToArray()
                Paths = $paths.ToArray()
            }
        }
        if ($nextPath -isnot [string]) {
            throw 'Pagination GetNextPath must return a string path or null.'
        }
        if ($pageNumber -ge $MaxPages) {
            throw "Pagination exceeded MaxPages ($MaxPages) before the resolver completed."
        }
        $currentPath = & $resolvePagePath $nextPath
    }
}

function Format-KritFixtureLogLine {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)][string]$Line)
    process {
        if (-not $Line) { return }
        $color = switch -Regex ($Line) {
            'FAIL|error|CRITICAL' { 'Red'; break }
            'PASS|success|OK\b' { 'Green'; break }
            'WARN|warning' { 'Yellow'; break }
            'INFO|status' { 'Cyan'; break }
            default { 'Gray' }
        }
        Write-Host $Line -ForegroundColor $color
    }
}

function Get-KritFixtureMode {
    <#
    .SYNOPSIS
        Read the protection mode
    .DESCRIPTION
        Read the protection mode

        HTTP: GET /api/settings/mode
        OpenAPI operationId: get_mode
    #>
    [CmdletBinding()]
    param(
        # scopes (header)
        [Parameter()]
        [string]$Scopes
    )
    process {
    $__kritQueryString = ''



        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking Get-KritFixtureMode' -Tag 'krit-openapi','fixture' -Data @{ method = 'GET'; path = '/api/settings/mode' }
        try {
    $headers = @{}
    if ($PSBoundParameters.ContainsKey('Scopes')) { $headers['scopes'] = $Scopes }
        Invoke-KritFixtureApi -Method GET -Path "/api/settings/mode$__kritQueryString" -Headers $headers
        } catch {
            Write-KritFixtureLog -Level Error -Message ('Get-KritFixtureMode failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

function Set-KritFixtureUpdateMode {
    <#
    .SYNOPSIS
        Set the protection mode
    .DESCRIPTION
        Set the protection mode

        HTTP: PUT /api/settings/mode
        OpenAPI operationId: update_mode
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # scopes (header)
        [Parameter()]
        [string]$Scopes,
        # mode (body)
        [Parameter()]
        [string]$Mode,
        # enabled (body)
        [Parameter()]
        [switch]$Enabled
    )
    process {
    $__kritQueryString = ''

        $__kritRequestBody = @{}
        if ($PSBoundParameters.ContainsKey('Mode')) { $__kritRequestBody += @{ 'mode' = $Mode } }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $__kritRequestBody += @{ 'enabled' = $Enabled.IsPresent } }

        if (-not $PSCmdlet.ShouldProcess('Fixture:/api/settings/mode', 'PUT')) { return }

        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking Set-KritFixtureUpdateMode' -Tag 'krit-openapi','fixture' -Data @{ method = 'PUT'; path = '/api/settings/mode' }
        try {
    $headers = @{}
    if ($PSBoundParameters.ContainsKey('Scopes')) { $headers['scopes'] = $Scopes }
        Invoke-KritFixtureApi -Method PUT -Path "/api/settings/mode$__kritQueryString" -Body $__kritRequestBody -ContentType 'application/json' -Headers $headers
        } catch {
            Write-KritFixtureLog -Level Error -Message ('Set-KritFixtureUpdateMode failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

function Get-KritFixtureListExceptions {
    <#
    .SYNOPSIS
        List allow-list entries
    .DESCRIPTION
        List allow-list entries

        HTTP: GET /api/exceptions
        OpenAPI operationId: list_exceptions
    #>
    [CmdletBinding()]
    param(
        # scopes (header)
        [Parameter()]
        [string]$Scopes
    )
    process {
    $__kritQueryString = ''



        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking Get-KritFixtureListExceptions' -Tag 'krit-openapi','fixture' -Data @{ method = 'GET'; path = '/api/exceptions' }
        try {
    $headers = @{}
    if ($PSBoundParameters.ContainsKey('Scopes')) { $headers['scopes'] = $Scopes }
        Invoke-KritFixtureApi -Method GET -Path "/api/exceptions$__kritQueryString" -Headers $headers
        } catch {
            Write-KritFixtureLog -Level Error -Message ('Get-KritFixtureListExceptions failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

function New-KritFixtureCreateException {
    <#
    .SYNOPSIS
        Create an allow-list entry
    .DESCRIPTION
        Create an allow-list entry

        HTTP: POST /api/exceptions
        OpenAPI operationId: create_exception
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # scopes (header)
        [Parameter()]
        [string]$Scopes,
        # requestData (body)
        [Parameter(Mandatory)]
        [hashtable]$RequestData
    )
    process {
    $__kritQueryString = ''

        $__kritRequestBody = @{
            'requestData' = $RequestData
        }

        if (-not $PSCmdlet.ShouldProcess('Fixture:/api/exceptions', 'POST')) { return }

        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking New-KritFixtureCreateException' -Tag 'krit-openapi','fixture' -Data @{ method = 'POST'; path = '/api/exceptions' }
        try {
    $headers = @{}
    if ($PSBoundParameters.ContainsKey('Scopes')) { $headers['scopes'] = $Scopes }
        Invoke-KritFixtureApi -Method POST -Path "/api/exceptions$__kritQueryString" -Body $__kritRequestBody -ContentType 'application/json' -Headers $headers
        } catch {
            Write-KritFixtureLog -Level Error -Message ('New-KritFixtureCreateException failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

function New-KritFixtureExceptionDelete {
    <#
    .SYNOPSIS
        Delete an allow-list entry
    .DESCRIPTION
        Delete an allow-list entry

        HTTP: POST /api/exceptions/delete/{id}
        OpenAPI operationId: exception_delete
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # id (path)
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [string]$ID
    )
    process {
    $__kritQueryString = ''


        if (-not $PSCmdlet.ShouldProcess('Fixture:/api/exceptions/delete/{id}', 'POST')) { return }

        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking New-KritFixtureExceptionDelete' -Tag 'krit-openapi','fixture' -Data @{ method = 'POST'; path = '/api/exceptions/delete/{id}' }
        try {
        Invoke-KritFixtureApi -Method POST -Path "/api/exceptions/delete/$([Uri]::EscapeDataString([string]$ID))$__kritQueryString"
        } catch {
            Write-KritFixtureLog -Level Error -Message ('New-KritFixtureExceptionDelete failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

function New-KritFixtureQueryEvents {
    <#
    .SYNOPSIS
        Read-only query (POST)
    .DESCRIPTION
        Read-only query (POST)

        HTTP: POST /api/query
        OpenAPI operationId: query_events
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # requestData (body)
        [Parameter()]
        [hashtable]$RequestData
    )
    process {
    $__kritQueryString = ''

        $__kritRequestBody = @{}
        if ($PSBoundParameters.ContainsKey('RequestData')) { $__kritRequestBody += @{ 'requestData' = $RequestData } }

        if (-not $PSCmdlet.ShouldProcess('Fixture:/api/query', 'POST')) { return }

        # Log the route template, never caller-supplied path/query values (which may be secrets).
        Write-KritFixtureLog -Level Verbose -Message 'Invoking New-KritFixtureQueryEvents' -Tag 'krit-openapi','fixture' -Data @{ method = 'POST'; path = '/api/query' }
        try {
        Invoke-KritFixtureApi -Method POST -Path "/api/query$__kritQueryString" -Body $__kritRequestBody -ContentType 'application/json'
        } catch {
            Write-KritFixtureLog -Level Error -Message ('New-KritFixtureQueryEvents failed: ' + $_.Exception.Message) -Tag 'krit-openapi','fixture','error'
            throw
        }
    }
}

Export-ModuleMember -Function Get-KritFixtureMode, Set-KritFixtureUpdateMode, Get-KritFixtureListExceptions, New-KritFixtureCreateException, New-KritFixtureExceptionDelete, New-KritFixtureQueryEvents, Invoke-KritFixtureApi, Format-KritFixtureLogLine, Get-KritFixtureBaseUri, Write-KritFixtureLog, Get-KritFixtureBanner, Write-KritFixtureBanner, Import-KritFixtureOmniSoft, Set-KritFixtureBaseUriProvider, Get-KritFixtureBaseUriProvider, Clear-KritFixtureBaseUriProvider, Set-KritFixtureTransportProvider, Get-KritFixtureTransportProvider, Clear-KritFixtureTransportProvider, Set-KritFixtureRequestHook, Get-KritFixtureRequestHook, Clear-KritFixtureRequestHook, Invoke-KritFixtureApiPages, Get-KritFixtureToken, Set-KritFixtureTokenProvider, Get-KritFixtureTokenProvider, Clear-KritFixtureTokenProvider
