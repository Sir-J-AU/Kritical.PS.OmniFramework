function Get-KriticalGraphProp {
    <#
    .SYNOPSIS
        Internal helper. Safely fetches a property/key from a Graph response object
        that may be a Hashtable, IDictionary or PSCustomObject, returning $null when
        the key is absent — even under Set-StrictMode -Version Latest.
    .NOTES
        Microsoft.Graph.Authentication / Invoke-MgGraphRequest returns Hashtables.
        StrictMode forbids direct $obj.SomeMissingKey access, so this helper is the
        canonical safe accessor across every OneDrive cmdlet in this module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Resolve-KriticalOneDriveDriveItem {
    <#
    .SYNOPSIS
        Internal helper. Resolves a local OneDrive-for-Business sync path to its
        cloud Microsoft Graph DriveItem and ensures a delegated Graph session.

    .DESCRIPTION
        Used by the public OneDrive sharing-link cmdlets (Get/Add/Set/Remove +
        New-KriticalOneDriveShareLink). Encapsulates:
          - Microsoft.Graph.Authentication import + Connect-MgGraph (delegated)
          - HKCU OneDrive Business1 sync-root lookup
          - Path mapping → /me/drive/root:/<encoded-relative-path>
          - Returning the DriveItem object (id / parentReference.driveId / etc)

        NOT exported. Kept private so the public surface stays narrow and the
        path/auth logic stays in one place.

    .NOTES
        CONTRACT
            inputs:
              - LocalPath        : path that must exist under HKCU OneDrive sync root
              - UseDeviceCode    : force device-code flow (headless)
              - Scopes           : Graph scopes to request (caller-specified)
            outputs:
              - PSCustomObject  : @{ Item, RelativePath, OdRoot, ResolvedLocal }
            sideEffects:
              - Connect-MgGraph (delegated, cached) when scopes missing/changed
              - No DriveItem mutation
            invariants:
              - Throws when path missing OR outside sync root OR DriveItem 404
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string[]]$Scopes,
        [switch]$UseDeviceCode
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Verbose "Installing Microsoft.Graph.Authentication ..."
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $resolvedLocal = (Resolve-Path -LiteralPath $LocalPath -ErrorAction Stop).Path

    $odBusinessRoot = $null
    try {
        $odBusinessRoot = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1' -Name UserFolder -ErrorAction Stop).UserFolder
    } catch {
        throw "OneDrive for Business sync root not found in HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1\UserFolder — verify OneDrive sync client signed in."
    }

    $resolvedLocal  = $resolvedLocal  -replace '\\','/' -replace '/$',''
    $odBusinessRoot = $odBusinessRoot -replace '\\','/' -replace '/$',''

    if (-not $resolvedLocal.StartsWith($odBusinessRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$resolvedLocal' is not under the OneDrive sync root '$odBusinessRoot' — only OneDrive-synced items can be managed."
    }

    $relativePath = $resolvedLocal.Substring($odBusinessRoot.Length).TrimStart('/')
    Write-Verbose "Local path:     $resolvedLocal"
    Write-Verbose "OneDrive root:  $odBusinessRoot"
    Write-Verbose "Cloud-relative: $relativePath"

    $ctx = Get-MgContext
    $needConnect = $true
    if ($ctx -and $ctx.Account) {
        $missingScope = $Scopes | Where-Object { $ctx.Scopes -notcontains $_ }
        if (-not $missingScope) {
            Write-Verbose "Already connected as $($ctx.Account)"
            $needConnect = $false
        }
    }
    if ($needConnect) {
        Write-Verbose "Connecting to Microsoft Graph (delegated, scopes: $($Scopes -join ', '))"
        if ($UseDeviceCode) {
            Connect-MgGraph -Scopes $Scopes -UseDeviceCode -NoWelcome -ErrorAction Stop
        } else {
            try {
                Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
            } catch {
                if ($_.Exception.Message -match 'window handle') {
                    Write-Verbose "Browser flow needs a window handle; falling back to device code."
                    Connect-MgGraph -Scopes $Scopes -UseDeviceCode -NoWelcome -ErrorAction Stop
                } else {
                    throw
                }
            }
        }
    }

    $encodedPath = ($relativePath -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $itemUri = "/v1.0/me/drive/root:/$encodedPath"
    Write-Verbose "Looking up: $itemUri"
    $item = Invoke-MgGraphRequest -Method GET -Uri $itemUri -ErrorAction Stop

    [pscustomobject]@{
        Item          = $item
        ItemId        = $item.id
        DriveId       = $item.parentReference.driveId
        ItemName      = $item.name
        IsFolder      = [bool]$item.folder
        RelativePath  = $relativePath
        OdRoot        = $odBusinessRoot
        ResolvedLocal = $resolvedLocal
    }
}
