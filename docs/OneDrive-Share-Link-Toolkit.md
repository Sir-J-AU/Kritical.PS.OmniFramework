# Kritical.PS.OmniFramework — OneDrive Share-Link Toolkit

5 PowerShell cmdlets to **mint, audit, add to, modify and revoke** Microsoft OneDrive for Business
share permissions from PowerShell, using delegated Microsoft Graph user-auth (no API keys, no
service principals). Designed for distributing customer-engagement packs, internal documents and
multi-recipient bundles by **share link** rather than by 10MB email attachment.

Shipped in **Kritical.PS.OmniFramework v1.1.12+** (the four management cmdlets in v1.1.13+; external-guest
email surfacing in v1.1.14+).

---

## Why this exists

- Email attachments cluster around mailbox quotas and gateway limits.
- Every minor refresh forces an email re-send (recipient gets N emails for N updates).
- A OneDrive share link is one URL the recipient saves once. Updates land automatically because
  the link target is **stable** — the operator can archive the prior content into a subfolder,
  drop new files in, re-zip, and the recipient simply re-clicks the same link.
- All five cmdlets use **user-delegated Microsoft Graph auth**: the operator signs in with their
  own M365 identity via WAM browser flow (or device-code fallback for headless contexts). No app
  registration, no client secret, no service principal, no API key.

---

## Install

```powershell
Install-Module Kritical.PS.OmniFramework -Scope CurrentUser
Import-Module Kritical.PS.OmniFramework -Force
```

Requires PowerShell 5.1+ or PowerShell 7. The cmdlets transparently install
`Microsoft.Graph.Authentication` on first use if it is not already present.

---

## The five cmdlets

| Cmdlet | Graph verb / endpoint | Purpose |
|---|---|---|
| `New-KriticalOneDriveShareLink`            | `POST /me/drive/items/{id}/createLink`    | Mint a share-link permission (view\|edit × anonymous\|organization\|users) |
| `Get-KriticalOneDriveShareLinkPermissions` | `GET  /me/drive/items/{id}/permissions`   | List every permission currently in force on a synced item |
| `Add-KriticalOneDriveShareLinkRecipients`  | `POST /me/drive/items/{id}/invite`        | Add named recipients WITHOUT disrupting any other permission |
| `Set-KriticalOneDriveShareLinkPermission`  | `PATCH /me/drive/items/{id}/permissions/{permId}` | Change role / expiry / password on an existing permission in place |
| `Remove-KriticalOneDriveShareLinkPermission` | `DELETE /me/drive/items/{id}/permissions/{permId}` | Revoke a single permission by ID |

All five resolve the local OneDrive sync path to its cloud DriveItem via
`HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1\UserFolder` → `/me/drive/root:/<path>`.
None of them touch other permissions on the item except the one being managed.

---

## Auth model

Delegated Graph scopes requested on every call: `Files.ReadWrite.All`, `Sites.ReadWrite.All`,
`User.Read`.

- **Default** — WAM browser flow. Needs a window handle, so works from a **normal pwsh window**
  but NOT from an embedded VS Code terminal subshell.
- **Headless / subshell** — pass `-UseDeviceCode` to fall back to device-code auth (visit the URL
  in any browser, enter the code).
- Token is cached per CurrentUser scope after first-run consent, so subsequent calls reuse the
  session without prompting.

---

## Quick start — typical lifecycle

```powershell
# 1. Mint a link to a folder you want to share
$share = New-KriticalOneDriveShareLink `
    -LocalPath 'C:\Users\you\OneDrive - Your Tenant\Customer\Engagement-FINAL-SHARED' `
    -ShareType edit `
    -ShareScope users `
    -Recipients @('teammate@yourtenant.com')

$share.WebUrl   # save this URL — it stays stable across content refreshes

# 2. See who has access right now
Get-KriticalOneDriveShareLinkPermissions -LocalPath 'C:\Users\you\OneDrive - Your Tenant\Customer\Engagement-FINAL-SHARED' |
    Format-Table Type, Roles, LinkScope, GrantedToEmails -AutoSize

# 3. Add another recipient (e.g. the customer) without disrupting the existing share
Add-KriticalOneDriveShareLinkRecipients `
    -LocalPath 'C:\Users\you\OneDrive - Your Tenant\Customer\Engagement-FINAL-SHARED' `
    -Recipients 'customer.contact@external.com' `
    -Role view

# 4. Refresh the folder contents (archive old, drop new, re-zip) — link URL stays the same.
#    The recipient keeps clicking the same URL and sees the latest content automatically.

# 5. Update someone's role in place (without revoking + re-inviting)
$perms = Get-KriticalOneDriveShareLinkPermissions -LocalPath '...' 
$lincoln = $perms | Where-Object { $_.GrantedToEmails -contains 'customer.contact@external.com' }
Set-KriticalOneDriveShareLinkPermission -LocalPath '...' -PermissionId $lincoln.PermissionId -Role edit

# 6. Add an expiry to an existing permission
Set-KriticalOneDriveShareLinkPermission -LocalPath '...' -PermissionId $lincoln.PermissionId `
    -ExpirationDateTime '2026-09-30T23:59:00Z'

# 7. Clear an existing expiry (empty string semantics)
Set-KriticalOneDriveShareLinkPermission -LocalPath '...' -PermissionId $lincoln.PermissionId `
    -ExpirationDateTime ''

# 8. Revoke a single recipient when the engagement closes
Get-KriticalOneDriveShareLinkPermissions -LocalPath '...' |
    Where-Object { $_.GrantedToEmails -contains 'customer.contact@external.com' } |
    ForEach-Object {
        Remove-KriticalOneDriveShareLinkPermission `
            -LocalPath '...' -PermissionId $_.PermissionId -Confirm:$false
    }
```

---

## Cmdlet reference

### `New-KriticalOneDriveShareLink`

Mint a fresh share-link permission. Idempotent for the same `(ShareScope, ShareType)` pair —
Graph returns the same `WebUrl` if a matching permission already exists.

```powershell
New-KriticalOneDriveShareLink `
    -LocalPath <string> `              # Required. Local OneDrive-synced path.
    [-ShareType view|edit]             # Default: view
    [-ShareScope anonymous|organization|users]  # Default: organization
    [-Recipients <string[]>]           # Required when ShareScope=users
    [-Password <string>]               # Only honoured for anonymous
    [-ExpirationDateTime <ISO 8601>]   # Only honoured for anonymous
    [-UseDeviceCode]                   # Headless / subshell auth fallback
```

Returns `PSCustomObject` — `WebUrl`, `ShareId`, `ItemId`, `DriveId`, `ItemName`, `IsFolder`,
`ShareType`, `ShareScope`, `CreatedAt`.

### `Get-KriticalOneDriveShareLinkPermissions`

List every permission on a local OneDrive-synced item. Read-only.

```powershell
Get-KriticalOneDriveShareLinkPermissions -LocalPath <string> [-UseDeviceCode]
```

Returns one `PSCustomObject` per permission — `PermissionId`, `Type` (`user`|`link`|`inheritance`|
`application`), `Roles`, `GrantedToEmails`, `GrantedToNames`, `LinkScope`, `LinkType`, `WebUrl`,
`ExpirationDateTime`, `HasPassword`, `Inherited`.

Internal tenant grants surface under `.user`; external-guest grants under `.siteUser` — the cmdlet
walks both (plus `.group`, `.application`, `.device`) and deduplicates the result.

### `Add-KriticalOneDriveShareLinkRecipients`

Add named recipients to an item **without touching any existing permission**. Calls
`POST /me/drive/items/{id}/invite`.

```powershell
Add-KriticalOneDriveShareLinkRecipients `
    -LocalPath <string> `              # Required
    -Recipients <string[]> `           # Required (internal + external emails)
    [-Role view|edit]                  # Default: view
    [-RequireSignIn $true|$false]      # Default: $true (secure default)
    [-SendInvitation]                  # Default: off (operator usually sends own cover email)
    [-Message <string>]                # Only honoured when -SendInvitation
    [-ExpirationDateTime <ISO 8601>]
    [-Password <string>]
    [-UseDeviceCode]
    [-WhatIf] [-Confirm]               # SupportsShouldProcess (ConfirmImpact = Medium)
```

Returns one `PSCustomObject` per newly-granted permission.

### `Set-KriticalOneDriveShareLinkPermission`

Update an existing permission in place — change role, set/clear expiry, set/clear password. Calls
`PATCH /me/drive/items/{id}/permissions/{permId}`.

```powershell
Set-KriticalOneDriveShareLinkPermission `
    -LocalPath <string> `              # Required
    -PermissionId <string> `           # Required (from Get-)
    [-Role view|edit]                  # Updates roles
    [-ExpirationDateTime <ISO 8601>]   # Pass '' to CLEAR an existing expiry
    [-Password <string>]               # Pass '' to CLEAR an existing password
    [-UseDeviceCode]
    [-WhatIf] [-Confirm]               # SupportsShouldProcess (ConfirmImpact = Medium)
```

At least one of `-Role` / `-ExpirationDateTime` / `-Password` must be supplied. Returns
`PSCustomObject` reflecting Graph's PATCH response.

### `Remove-KriticalOneDriveShareLinkPermission`

Revoke a single permission by ID. Other permissions on the item are not touched. Calls
`DELETE /me/drive/items/{id}/permissions/{permId}`.

```powershell
Remove-KriticalOneDriveShareLinkPermission `
    -LocalPath <string> `              # Required
    -PermissionId <string> `           # Required (from Get-)
    [-UseDeviceCode]
    [-WhatIf] [-Confirm]               # SupportsShouldProcess (ConfirmImpact = High)
```

`ConfirmImpact = High` means the cmdlet prompts by default — pass `-Confirm:$false` to skip the
prompt in pipeline / scripted use.

---

## End-to-end recipe — customer-engagement pack distribution

Standard pattern for distributing a multi-document customer proposal pack:

1. **Render the pack** with whatever build script you use (PDF + DOCX + HTML).
2. **Create the share folder** in OneDrive, conventionally
   `<Customer>/<Engagement>-FINAL-SHARED/`.
3. **Mint the share link** to your internal team:
   ```powershell
   New-KriticalOneDriveShareLink -LocalPath <pack-folder> -ShareType edit -ShareScope users `
       -Recipients @('teammate1@yourtenant.com','teammate2@yourtenant.com')
   ```
4. **Add the customer contact** as view-only:
   ```powershell
   Add-KriticalOneDriveShareLinkRecipients -LocalPath <pack-folder> `
       -Recipients 'customer@external.com' -Role view
   ```
5. **Send your own cover email** with the share URL — operators almost always prefer their own
   branded message over Microsoft's transactional template (so `-SendInvitation` is off by
   default).
6. **Refresh the pack later** by archiving the prior contents into a `_ARCHIVED-<utc>-<reason>/`
   subfolder (never delete — preserves history), dropping the new revision, re-zipping. The share
   URL is unchanged so every recipient picks up the update automatically.
7. **Audit** any time with `Get-KriticalOneDriveShareLinkPermissions` to confirm who has access.
8. **Revoke** the customer when the engagement closes via `Remove-...` filtered by their email.

---

## Permission types — what shows up in `Get-`

The `Type` column in the Get output tells you what kind of permission Graph reports:

| Type | What it means |
|---|---|
| `link`        | A share-link permission (mintable via `New-KriticalOneDriveShareLink`). `LinkScope` + `LinkType` tell you the scope/role; `WebUrl` is the URL itself. |
| `user`        | A direct user / guest grant (produced by `Add-KriticalOneDriveShareLinkRecipients` via `/invite`). |
| `inheritance` | A permission inherited from a parent folder. Don't try to delete these on the child — go to the parent. |
| `application` | A service-principal grant (rare in user-delegated contexts; usually appears for first-party Microsoft apps). |

The `owner` role on Joshua's row in the worked example is the drive owner — always present, can't
be removed.

---

## Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `Connect-MgGraph: InteractiveBrowserCredential authentication failed: A window handle must be configured` | Running from a subshell with no window (e.g. VS Code embedded terminal) | Re-run from a normal pwsh window, OR pass `-UseDeviceCode` |
| `The property 'grantedToIdentitiesV2' cannot be found on this object` | Old version of Kritical.PS.OmniFramework (pre-1.1.13) still installed | Update: `Install-Module Kritical.PS.OmniFramework -Force -Scope CurrentUser` and re-import |
| `OneDrive for Business sync root not found in registry...` | OneDrive sync client not signed in on this machine | Sign in to OneDrive for Business; re-try |
| `Path '...' is not under the OneDrive sync root '...'` | LocalPath is somewhere outside the synced OneDrive Business1 root | Move the folder into the OneDrive sync tree (or point LocalPath at one inside it) |
| 404 from Graph on `Remove-` / `Set-` | PermissionId no longer exists (already revoked, or wrong ID) | Re-run `Get-` to get a current list |
| Lincoln's email shows empty in `Get-` output | You're on Kritical.PS.OmniFramework < 1.1.14 (external-guest emails landed under `siteUser` not `user`) | Upgrade to 1.1.14+ |

---

## Security posture

- **No API keys.** All calls use the operator's delegated M365 identity. No client secret, no
  service principal, no token stored on disk in cleartext.
- **No outbound data exfiltration.** Every Graph call targets the operator's own drive (`/me/drive`).
- **Existing permissions are never silently mutated.** `Add-` adds, `Set-` only modifies the
  PermissionId you specify, `Remove-` only deletes the PermissionId you specify.
- **`Remove-` defaults to confirm-prompt** (`ConfirmImpact = High`). Pass `-Confirm:$false` when
  scripting.
- **External-guest invites default `-RequireSignIn = $true`** — even external emails must sign
  in via their email (Microsoft creates a guest account on demand). Pass `-RequireSignIn:$false`
  for an anonymous-style invite gated by email alone (less secure; not recommended for
  customer-facing engagement packs).
- **Password and ExpirationDateTime** only honoured by Graph on anonymous-scope links — Graph
  silently ignores them on `users`-scope or direct invites.

---

## Related

- Module source: [src/Public/](../src/Public/) — one file per cmdlet
- Private resolver shared helper: [src/Private/_KritOneDriveResolver.ps1](../src/Private/_KritOneDriveResolver.ps1)
- Surface-contract tests: [tests/Unit/OneDriveShareLink.Tests.ps1](../tests/Unit/OneDriveShareLink.Tests.ps1)
  and [tests/Unit/OneDriveShareLinkPermissions.Tests.ps1](../tests/Unit/OneDriveShareLinkPermissions.Tests.ps1)
- Module overview: [README.md](../README.md)
- Architecture: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- Publishing: [docs/PUBLISHING.md](PUBLISHING.md)

---

Author: Joshua Finley — Kritical Pty Ltd — <https://kritical.net>
Module: Kritical.PS.OmniFramework — <https://github.com/Sir-J-AU/Kritical.PS.OmniFramework>
License: MIT — see [LICENSE](../LICENSE)
