function New-KriticalOneDriveShareLink {
    <#
    .SYNOPSIS
        Generate a Microsoft Graph OneDrive sharing link for a local OneDrive-synced file or folder
        and return the URL + metadata as a PSCustomObject.

    .DESCRIPTION
        Uses user-delegated Microsoft Graph auth (Files.ReadWrite.All + Sites.ReadWrite.All +
        User.Read scopes) to mint a `createLink` permission on a DriveItem in the operator's
        personal OneDrive for Business drive. Maps the local OneDrive sync path to the cloud
        DriveItem by reading the sync root from HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1
        and the path-relative `/me/drive/root:/<path>` Graph endpoint.

        Use cases:
          • Send a customer-engagement folder to internal reviewers (Ben / Josh / etc.) without
            10 MB email attachments.
          • Generate time-limited / password-protected anonymous links for external sharing.
          • Build customer-folder share-links into engagement-letter / SOW generation pipelines.

        Auth flow:
          • Default: interactive browser via WAM (needs a window handle — works from a normal
            PowerShell window, not from an embedded terminal subshell).
          • Fallback: device-code (set -UseDeviceCode) for headless contexts.
          • First-run consent only — token cached per CurrentUser scope after that.

        Security posture: Microsoft Graph user-delegated auth using the operator's M365
        identity. No API keys. No service-principal client secrets in scripts. The operator
        signs in with their M365 account; Graph caches the delegated token via the standard
        Microsoft.Graph.Authentication module.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.
        Must exist locally. Will be resolved + validated against the registered sync root.

    .PARAMETER ShareType
        view (default) | edit. Maps to the Graph `link.type` value.

    .PARAMETER ShareScope
        organization (default) | anonymous | users. Maps to the Graph `link.scope` value.

        anonymous   — anyone with the link can access (use Password / ExpirationDateTime to
                      tighten); useful for one-off external shares.
        organization — anyone in the operator's tenant who's signed in (default; safest
                       internal-only share).
        users       — explicit named-recipient access; pair with -Recipients. Most-restrictive.

    .PARAMETER Recipients
        Email-address array. REQUIRED when ShareScope = users. Ignored otherwise.

    .PARAMETER Password
        Optional password gate for anonymous links. Only honoured by Graph when ShareScope = anonymous.

    .PARAMETER ExpirationDateTime
        Optional ISO 8601 expiry. Only honoured by Graph when ShareScope = anonymous.

    .PARAMETER UseDeviceCode
        Force device-code auth flow (browser fallback). Use this in headless / embedded-terminal
        contexts where WAM cannot acquire a window handle.

    .EXAMPLE
        $share = New-KriticalOneDriveShareLink -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/EES/EES-proposal-pack-FINAL-SHARED'
        $share.WebUrl
        # https://kriticalptyltd-my.sharepoint.com/:f:/g/personal/joshua_finley_kritical_net/...

        Generates a tenant-scoped view link for the EES proposal pack folder.

    .EXAMPLE
        $share = New-KriticalOneDriveShareLink -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/EES/folder' -ShareType edit -ShareScope users -Recipients @('ben.szypowski@kritical.net','joshua.finley@kritical.net')

        Generates an edit-scope named-recipient link for Ben + Josh.

    .EXAMPLE
        $share = New-KriticalOneDriveShareLink -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/Customer/folder' -ShareScope anonymous -Password 'OneTime-2026' -ExpirationDateTime '2026-07-31T17:00:00Z'

        Generates a password-protected anonymous link expiring 31 Jul 2026 — for one-off external sharing.

    .OUTPUTS
        PSCustomObject with these properties:
          WebUrl     [string]  — the sharing URL to send
          ShareId    [string]  — Graph share-permission ID (use for revocation)
          ItemId    [string]  — DriveItem ID
          DriveId    [string]  — parent Drive ID
          ItemName   [string]  — file/folder name
          IsFolder   [bool]
          ShareType  [string]  — view|edit (echoed back)
          ShareScope [string]  — anonymous|organization|users (echoed back)
          CreatedAt  [string]  — ISO 8601 timestamp of link creation

    .NOTES
        CONTRACT
            inputs:
              - LocalPath        : path; must exist + be under OneDrive sync root
              - ShareType        : view|edit
              - ShareScope       : anonymous|organization|users
              - Recipients       : email[] (required when ShareScope=users)
              - Password         : optional (anonymous only)
              - ExpirationDateTime: optional ISO 8601 (anonymous only)
            outputs:
              - PSCustomObject with WebUrl + ShareId + ItemId + DriveId + ItemName + IsFolder
                + ShareType + ShareScope + CreatedAt
            sideEffects:
              - Connects to Microsoft Graph (delegated; cached per CurrentUser)
              - Creates a sharing-link permission on the target DriveItem (visible in OneDrive admin)
              - Does NOT modify the item bytes
              - Does NOT send the link itself (caller wires into email / message)
            invariants:
              - Returns WebUrl only after the createLink Graph response is received
              - Throws on path-outside-sync-root, item-not-found, auth-failure
              - asserts: paired tests/Unit/OneDriveShareLink.Tests.ps1

        Author:  Joshua Finley
        Repo:    Kritical.PS.OmniFramework
        Promoted-from: Kritical-M365DSC/management/New-KriticalOneDriveShareLink.ps1 (2026-06-28)
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword','Password',
        Justification = 'Microsoft Graph /createLink contract requires a plaintext password field on the request body (only honoured for anonymous-scope links); converting to SecureString would force an unwrap that defeats the protection. Operator-supplied password lives in memory for the single call only.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [ValidateSet('view','edit')]
        [string]$ShareType = 'view',

        [ValidateSet('anonymous','organization','users')]
        [string]$ShareScope = 'organization',

        [string[]]$Recipients,

        [string]$Password,

        [string]$ExpirationDateTime,

        [switch]$UseDeviceCode
    )

    # --- 1. Ensure Microsoft Graph Authentication module present (Invoke-MgGraphRequest is all we need; we use raw REST below) ---
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Verbose "Installing Microsoft.Graph.Authentication ..."
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    # --- 2. Resolve local path → OneDrive cloud-relative path ---
    $resolvedLocal = (Resolve-Path -LiteralPath $LocalPath -ErrorAction Stop).Path

    $odBusinessRoot = $null
    try {
        $odBusinessRoot = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1' -Name UserFolder -ErrorAction Stop).UserFolder
    } catch {
        throw "OneDrive for Business sync root not found in registry HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1\UserFolder — verify OneDrive sync client signed in."
    }

    $resolvedLocal   = $resolvedLocal   -replace '\\','/' -replace '/$',''
    $odBusinessRoot  = $odBusinessRoot  -replace '\\','/' -replace '/$',''

    if (-not $resolvedLocal.StartsWith($odBusinessRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$resolvedLocal' is not under the OneDrive sync root '$odBusinessRoot' — only OneDrive-synced files can be shared."
    }

    $relativePath = $resolvedLocal.Substring($odBusinessRoot.Length).TrimStart('/')
    Write-Verbose "Local path:     $resolvedLocal"
    Write-Verbose "OneDrive root:  $odBusinessRoot"
    Write-Verbose "Cloud-relative: $relativePath"

    # --- 3. Connect to Microsoft Graph (delegated; cached token re-used if scopes match) ---
    $graphScopes = @('Files.ReadWrite.All','Sites.ReadWrite.All','User.Read')
    $ctx = Get-MgContext
    $needConnect = $true
    if ($ctx -and $ctx.Account) {
        $missingScope = $graphScopes | Where-Object { $ctx.Scopes -notcontains $_ }
        if (-not $missingScope) {
            Write-Verbose "Already connected as $($ctx.Account)"
            $needConnect = $false
        }
    }
    if ($needConnect) {
        Write-Verbose "Connecting to Microsoft Graph (delegated, scopes: $($graphScopes -join ', '))"
        if ($UseDeviceCode) {
            Connect-MgGraph -Scopes $graphScopes -UseDeviceCode -NoWelcome -ErrorAction Stop
        } else {
            try {
                Connect-MgGraph -Scopes $graphScopes -NoWelcome -ErrorAction Stop
            } catch {
                if ($_.Exception.Message -match 'window handle') {
                    Write-Verbose "Browser flow needs a window handle; falling back to device code."
                    Connect-MgGraph -Scopes $graphScopes -UseDeviceCode -NoWelcome -ErrorAction Stop
                } else {
                    throw
                }
            }
        }
    }

    # --- 4. Look up DriveItem by path ---
    $encodedPath = ($relativePath -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $itemUri = "/v1.0/me/drive/root:/$encodedPath"
    Write-Verbose "Looking up: $itemUri"
    $item = Invoke-MgGraphRequest -Method GET -Uri $itemUri -ErrorAction Stop
    Write-Verbose "Found DriveItem: $($item.id) — $($item.name) — $(if ($item.folder) {'(folder)'} else {'(file)'})"

    # --- 5. Create the sharing link ---
    $linkBody = @{
        type  = $ShareType
        scope = $ShareScope
    }
    if ($Password)           { $linkBody.password = $Password }
    if ($ExpirationDateTime) { $linkBody.expirationDateTime = $ExpirationDateTime }
    if ($Recipients -and $ShareScope -eq 'users') {
        $linkBody.recipients = @($Recipients | ForEach-Object { @{ email = $_ } })
    }

    $createUri = "/v1.0/me/drive/items/$($item.id)/createLink"
    $linkBodyJson = $linkBody | ConvertTo-Json -Depth 5 -Compress
    Write-Verbose "Creating $ShareType / $ShareScope link"
    $linkResp = Invoke-MgGraphRequest -Method POST -Uri $createUri -Body $linkBodyJson -ContentType 'application/json' -ErrorAction Stop

    [pscustomobject]@{
        WebUrl     = $linkResp.link.webUrl
        ShareId    = $linkResp.id
        ItemId     = $item.id
        DriveId    = $item.parentReference.driveId
        ItemName   = $item.name
        IsFolder   = [bool]$item.folder
        ShareType  = $ShareType
        ShareScope = $ShareScope
        CreatedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
