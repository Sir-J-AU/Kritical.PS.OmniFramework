function Remove-KriticalOneDriveShareLinkPermission {
    <#
    .SYNOPSIS
        Revoke a single OneDrive share permission by its PermissionId.

    .DESCRIPTION
        Calls Microsoft Graph `DELETE /me/drive/items/{id}/permissions/{permId}`.
        Find the PermissionId via Get-KriticalOneDriveShareLinkPermissions.

        Use cases:
          • Customer engagement ends — revoke external recipient access.
          • Internal staff leaves — pull their personal share permissions.
          • Anonymous link no longer required — kill the link permission.
          • Mistaken share — revert.

        Other permissions on the same item are NOT touched.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.

    .PARAMETER PermissionId
        The Graph permission ID to revoke (from Get-KriticalOneDriveShareLinkPermissions).

    .PARAMETER UseDeviceCode
        Force device-code auth flow for headless contexts.

    .EXAMPLE
        Get-KriticalOneDriveShareLinkPermissions -LocalPath $f | Where-Object { $_.GrantedToEmails -contains 'lincoln@eeservices.io' } | ForEach-Object { Remove-KriticalOneDriveShareLinkPermission -LocalPath $f -PermissionId $_.PermissionId -Confirm:$false }

        Revoke Lincoln's access after the engagement closes.

    .EXAMPLE
        Remove-KriticalOneDriveShareLinkPermission -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/EES/EES-proposal-pack-FINAL-SHARED' -PermissionId 'aTowIy5xLnxs...'

        Revoke a specific permission by ID.

    .OUTPUTS
        PSCustomObject:
          PermissionId  [string]  ID that was revoked
          Removed       [bool]    true on Graph 204 No Content
          ItemName      [string]
          RemovedAt     [string]  ISO 8601

    .NOTES
        CONTRACT
            inputs:
              - LocalPath        : path; must exist + be under OneDrive sync root
              - PermissionId     : Graph permission ID; required
            outputs:
              - PSCustomObject with PermissionId / Removed / ItemName / RemovedAt
            sideEffects:
              - Connects to Microsoft Graph (Files.ReadWrite.All + Sites.ReadWrite.All)
              - Deletes the specified permission on the target DriveItem
              - Other permissions on the same item are NOT touched
            invariants:
              - Permission ID must already exist; Graph returns 404 otherwise (re-raised)
              - asserts: paired tests/Unit/OneDriveShareLinkPermissions.Tests.ps1

        Author:  Joshua Finley
        Repo:    Kritical.PS.OmniFramework
        Added:   v1.1.13 — Kritical.PS.OmniFramework 2026-06-28 (.1507ab)
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$PermissionId,
        [switch]$UseDeviceCode
    )

    $scopes = @('Files.ReadWrite.All','Sites.ReadWrite.All','User.Read')
    $resolved = Resolve-KriticalOneDriveDriveItem -LocalPath $LocalPath -Scopes $scopes -UseDeviceCode:$UseDeviceCode

    $action = "Revoke permission $PermissionId on $($resolved.ItemName)"
    if (-not $PSCmdlet.ShouldProcess($resolved.ItemName, $action)) { return }

    $permUri = "/v1.0/me/drive/items/$($resolved.ItemId)/permissions/$PermissionId"
    Write-Verbose "Deleting: $permUri"
    # .5231 (lens-hunt): HR16 idempotency. Graph returns 404 when the permission is
    # already gone; a second call must not throw. Swallow not-found and still report
    # Removed=$true so re-runs converge on the same 'permission absent' end-state.
    try {
        Invoke-MgGraphRequest -Method DELETE -Uri $permUri -ErrorAction Stop | Out-Null
    }
    catch {
        $isNotFound = $false
        $ex = $_.Exception
        if ($ex.PSObject.Properties['Response'] -and $ex.Response -and
            $ex.Response.PSObject.Properties['StatusCode'] -and [int]$ex.Response.StatusCode -eq 404) {
            $isNotFound = $true
        }
        elseif ($_.ErrorDetails -and $_.ErrorDetails.Message -match '(?i)itemNotFound|not\s*found|404') {
            $isNotFound = $true
        }
        elseif ($_ -match '(?i)itemNotFound|not\s*found|404') {
            $isNotFound = $true
        }
        if (-not $isNotFound) { throw }
        Write-Verbose "Permission $PermissionId already absent (404) — treating as removed (idempotent)."
    }

    [pscustomobject]@{
        PermissionId = $PermissionId
        Removed      = $true
        ItemName     = $resolved.ItemName
        RemovedAt    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
