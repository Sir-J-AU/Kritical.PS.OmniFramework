function Remove-KriticalOneDriveShareLinkPermission {
    <#
    .SYNOPSIS
        Revoke a specific OneDrive share permission by permission ID.

    .DESCRIPTION
        Resolves the local OneDrive path to its DriveItem and deletes the named permission
        through Microsoft Graph. Deleting an already-absent permission is idempotent: Graph
        404/itemNotFound is treated as the desired final state and returns Removed=$true.
        Non-not-found failures still propagate.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.

    .PARAMETER PermissionId
        The Graph permission ID to revoke.

    .PARAMETER UseDeviceCode
        Force device-code auth flow for headless contexts.

    .EXAMPLE
        Remove-KriticalOneDriveShareLinkPermission -LocalPath $f -PermissionId 'aTowIy5...' -Confirm:$false

    .OUTPUTS
        PSCustomObject with PermissionId, Removed, ItemName and RemovedAt.

    .NOTES
        CONTRACT
            inputs:
              - LocalPath    : path; must resolve to a OneDrive DriveItem
              - PermissionId : Graph permission ID; required
            outputs:
              - PSCustomObject recording permission-absent convergence
            sideEffects:
              - Connects to Microsoft Graph (Files.ReadWrite.All + Sites.ReadWrite.All)
              - Deletes only the named permission when it exists
            invariants:
              - Graph 404/itemNotFound means the desired permission-absent state already holds and returns Removed=true
              - non-404/non-not-found Graph errors are re-raised
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
