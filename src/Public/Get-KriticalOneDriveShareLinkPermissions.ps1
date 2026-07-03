function Get-KriticalOneDriveShareLinkPermissions {
    <#
    .SYNOPSIS
        List every share permission currently in force on a local OneDrive-synced item.

    .DESCRIPTION
        Resolves a local OneDrive-for-Business path to its cloud DriveItem and calls
        Microsoft Graph `GET /me/drive/items/{id}/permissions`. Returns one row per
        permission (named users, anonymous links, organization links) with the
        permission ID needed to revoke or modify it via Remove- / Set-.

        Use cases:
          • Audit who currently has access to a customer-engagement share folder.
          • Find the PermissionId of a recipient before revoking.
          • Verify that adding/removing recipients took effect.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.

    .PARAMETER UseDeviceCode
        Force device-code auth flow (browser fallback) for headless contexts.

    .EXAMPLE
        Get-KriticalOneDriveShareLinkPermissions -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/EES/EES-proposal-pack-FINAL-SHARED'

        Lists every permission on the EES share folder.

    .EXAMPLE
        Get-KriticalOneDriveShareLinkPermissions -LocalPath $f | Where-Object Type -eq 'link' | Select-Object PermissionId, LinkScope, LinkType, WebUrl

        Just the share-link permissions (excluding direct user grants).

    .EXAMPLE
        Get-KriticalOneDriveShareLinkPermissions -LocalPath $f | Where-Object { $_.GrantedToEmails -contains 'lincoln@eeservices.io' }

        Find Lincoln's permission row before revoking.

    .OUTPUTS
        PSCustomObject (one per permission) with:
          PermissionId       [string]
          Type               [string]  'user' | 'link' | 'inheritance' | 'application'
          Roles              [string[]] e.g. @('read'), @('write')
          GrantedToEmails    [string[]] direct user grants (when Type=user/users)
          GrantedToNames     [string[]]
          LinkScope          [string]  'anonymous' | 'organization' | 'users' | $null
          LinkType           [string]  'view' | 'edit' | 'embed' | $null
          WebUrl             [string]  share URL (when Type=link)
          ExpirationDateTime [string]  ISO 8601 or $null
          HasPassword        [bool]
          Inherited          [bool]

    .NOTES
        CONTRACT
            inputs:
              - LocalPath        : path; must exist + be under OneDrive sync root
              - UseDeviceCode    : switch
            outputs:
              - PSCustomObject[] (one per permission row from Graph)
            sideEffects:
              - Connects to Microsoft Graph (Files.ReadWrite.All + Sites.ReadWrite.All)
              - Read-only — no DriveItem or permission mutation
            invariants:
              - Throws on path-outside-sync-root, item-not-found, auth-failure
              - asserts: paired tests/Unit/OneDriveShareLinkPermissions.Tests.ps1

        Author:  Joshua Finley
        Repo:    Kritical.PS.OmniFramework
        Added:   v1.1.13 — Kritical.PS.OmniFramework 2026-06-28 (.1507ab)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [switch]$UseDeviceCode
    )

    $scopes = @('Files.ReadWrite.All','Sites.ReadWrite.All','User.Read')
    $resolved = Resolve-KriticalOneDriveDriveItem -LocalPath $LocalPath -Scopes $scopes -UseDeviceCode:$UseDeviceCode

    $permsUri = "/v1.0/me/drive/items/$($resolved.ItemId)/permissions"
    Write-Verbose "Listing permissions: $permsUri"
    $resp = Invoke-MgGraphRequest -Method GET -Uri $permsUri -ErrorAction Stop

    $rows = @(Get-KriticalGraphProp -Object $resp -Name 'value')
    foreach ($p in $rows) {
        $link    = Get-KriticalGraphProp -Object $p -Name 'link'
        $inh     = Get-KriticalGraphProp -Object $p -Name 'inheritedFrom'
        $idV2    = Get-KriticalGraphProp -Object $p -Name 'grantedToIdentitiesV2'
        $gV2     = Get-KriticalGraphProp -Object $p -Name 'grantedToV2'

        $type =
            if     ($link) { 'link' }
            elseif ($inh)  { 'inheritance' }
            elseif ($gV2 -or $idV2) { 'user' }
            else { 'application' }

        $emails = @()
        $names  = @()
        foreach ($g in @($idV2) + @($gV2)) {
            if ($null -eq $g) { continue }
            # Internal tenant users land under .user; external/guest invites
            # land under .siteUser with .loginName carrying the email.
            foreach ($idKey in 'user','siteUser','group','application','device') {
                $u = Get-KriticalGraphProp -Object $g -Name $idKey
                if ($null -eq $u) { continue }
                $em = Get-KriticalGraphProp -Object $u -Name 'email'
                if (-not $em) { $em = Get-KriticalGraphProp -Object $u -Name 'loginName' }
                $dn = Get-KriticalGraphProp -Object $u -Name 'displayName'
                if ($em) { $emails += $em }
                if ($dn) { $names  += $dn }
            }
        }

        [pscustomobject]@{
            PermissionId       = Get-KriticalGraphProp -Object $p -Name 'id'
            Type               = $type
            Roles              = @(Get-KriticalGraphProp -Object $p -Name 'roles')
            GrantedToEmails    = @($emails | Select-Object -Unique)
            GrantedToNames     = @($names  | Select-Object -Unique)
            LinkScope          = if ($link) { Get-KriticalGraphProp -Object $link -Name 'scope'  } else { $null }
            LinkType           = if ($link) { Get-KriticalGraphProp -Object $link -Name 'type'   } else { $null }
            WebUrl             = if ($link) { Get-KriticalGraphProp -Object $link -Name 'webUrl' } else { $null }
            ExpirationDateTime = Get-KriticalGraphProp -Object $p -Name 'expirationDateTime'
            HasPassword        = [bool](Get-KriticalGraphProp -Object $p -Name 'hasPassword')
            Inherited          = [bool]$inh
        }
    }
}
