function Set-KriticalOneDriveShareLinkPermission {
    <#
    .SYNOPSIS
        Update an existing OneDrive share permission in place — change roles, set/clear
        expiry, or update password — without revoking or recreating the permission.

    .DESCRIPTION
        Calls Microsoft Graph `PATCH /me/drive/items/{id}/permissions/{permId}` against
        the specified permission. Each named parameter that you pass is forwarded as a
        PATCH field; omitted parameters leave that field unchanged. The PermissionId
        and any other permissions on the item are NOT affected.

        Use cases:
          • Flip an internal reviewer from view → edit (or vice versa).
          • Add / extend / remove an expiry without losing the existing recipient grant.
          • Update the password on a password-gated anonymous link.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.

    .PARAMETER PermissionId
        The Graph permission ID to update (from Get-KriticalOneDriveShareLinkPermissions).

    .PARAMETER Role
        view|edit. When set, PATCHes `roles` to ['read'] or ['write'].

    .PARAMETER ExpirationDateTime
        New ISO 8601 expiry. Pass empty string '' to CLEAR an existing expiry.

    .PARAMETER Password
        New password gate. Pass empty string '' to CLEAR an existing password.
        Only honoured on link permissions whose scope is `anonymous`.

    .PARAMETER UseDeviceCode
        Force device-code auth flow for headless contexts.

    .EXAMPLE
        Set-KriticalOneDriveShareLinkPermission -LocalPath $f -PermissionId 'aTowIy5...' -Role edit

        Promote a view-only recipient to edit.

    .EXAMPLE
        Set-KriticalOneDriveShareLinkPermission -LocalPath $f -PermissionId 'aTowIy5...' -ExpirationDateTime '2026-09-30T23:59:00Z'

        Extend a recipient's expiry to end of Sept 2026.

    .EXAMPLE
        Set-KriticalOneDriveShareLinkPermission -LocalPath $f -PermissionId 'aTowIy5...' -ExpirationDateTime ''

        Clear an existing expiry (permanent access until manually revoked).

    .OUTPUTS
        PSCustomObject:
          PermissionId       [string]
          Roles              [string[]]  (updated)
          ExpirationDateTime [string]    (updated, may be $null)
          HasPassword        [bool]      (updated)
          ItemName           [string]
          UpdatedAt          [string]    ISO 8601

    .NOTES
        CONTRACT
            inputs:
              - LocalPath          : path; must exist + be under OneDrive sync root
              - PermissionId       : Graph permission ID; required
              - Role               : view|edit (optional)
              - ExpirationDateTime : ISO 8601 OR '' to clear (optional)
              - Password           : string OR '' to clear (optional)
            outputs:
              - PSCustomObject reflecting Graph's PATCH response
            sideEffects:
              - Connects to Microsoft Graph (Files.ReadWrite.All + Sites.ReadWrite.All)
              - Mutates the specified permission only; other permissions untouched
            invariants:
              - At least one of -Role / -ExpirationDateTime / -Password must be supplied
                (otherwise nothing to PATCH and cmdlet throws)
              - asserts: paired tests/Unit/OneDriveShareLinkPermissions.Tests.ps1

        Author:  Joshua Finley
        Repo:    Kritical.PS.OmniFramework
        Added:   v1.1.13 — Kritical.PS.OmniFramework 2026-06-28 (.1507ab)
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$PermissionId,
        [ValidateSet('view','edit')][string]$Role,
        [AllowEmptyString()][string]$ExpirationDateTime,
        [AllowEmptyString()][string]$Password,
        [switch]$UseDeviceCode
    )

    if (-not $PSBoundParameters.ContainsKey('Role') -and
        -not $PSBoundParameters.ContainsKey('ExpirationDateTime') -and
        -not $PSBoundParameters.ContainsKey('Password')) {
        throw "Set-KriticalOneDriveShareLinkPermission requires at least one of -Role / -ExpirationDateTime / -Password."
    }

    $scopes = @('Files.ReadWrite.All','Sites.ReadWrite.All','User.Read')
    $resolved = Resolve-KriticalOneDriveDriveItem -LocalPath $LocalPath -Scopes $scopes -UseDeviceCode:$UseDeviceCode

    $body = @{}
    if ($PSBoundParameters.ContainsKey('Role')) {
        $body.roles = @(if ($Role -eq 'edit') { 'write' } else { 'read' })
    }
    if ($PSBoundParameters.ContainsKey('ExpirationDateTime')) {
        $body.expirationDateTime = if ($ExpirationDateTime -eq '') { $null } else { $ExpirationDateTime }
    }
    if ($PSBoundParameters.ContainsKey('Password')) {
        $body.password = if ($Password -eq '') { $null } else { $Password }
    }

    $action = "Update permission $PermissionId on $($resolved.ItemName) — fields: $($body.Keys -join ', ')"
    if (-not $PSCmdlet.ShouldProcess($resolved.ItemName, $action)) { return }

    $permUri  = "/v1.0/me/drive/items/$($resolved.ItemId)/permissions/$PermissionId"
    $bodyJson = $body | ConvertTo-Json -Depth 5 -Compress
    Write-Verbose "PATCH: $permUri  $bodyJson"
    $resp = Invoke-MgGraphRequest -Method PATCH -Uri $permUri -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop

    # .5231 (lens-hunt): Invoke-MgGraphRequest returns a Hashtable; under Set-StrictMode
    # -Version Latest direct member access ($resp.id) throws. Use the canonical safe accessor.
    [pscustomobject]@{
        PermissionId       = Get-KriticalGraphProp -Object $resp -Name 'id'
        Roles              = @(Get-KriticalGraphProp -Object $resp -Name 'roles')
        ExpirationDateTime = Get-KriticalGraphProp -Object $resp -Name 'expirationDateTime'
        HasPassword        = [bool](Get-KriticalGraphProp -Object $resp -Name 'hasPassword')
        ItemName           = $resolved.ItemName
        UpdatedAt          = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
