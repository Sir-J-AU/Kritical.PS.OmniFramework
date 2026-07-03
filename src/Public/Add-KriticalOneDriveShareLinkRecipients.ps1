function Add-KriticalOneDriveShareLinkRecipients {
    <#
    .SYNOPSIS
        Grant additional named recipients access to an existing OneDrive-synced item
        WITHOUT disrupting any other permissions already in force on it.

    .DESCRIPTION
        Calls Microsoft Graph `POST /me/drive/items/{id}/invite` to add one or more
        recipients (internal users OR external email addresses) to the existing
        share permission set. The existing permissions (e.g. an earlier `users`-scope
        share already granted to Josh + Ben) stay untouched — this cmdlet only ADDS.

        Use cases:
          • Add a customer contact (e.g. Lincoln) to a proposal-pack folder already
            shared internally to your delivery team.
          • Quickly grant a new internal reviewer view-access to an existing share.
          • Send a Graph-tracked invitation email with a custom message.

    .PARAMETER LocalPath
        Full path to a file or folder under the OneDrive for Business sync root.

    .PARAMETER Recipients
        Email-address array. External emails work too (per SharePoint external-sharing policy).

    .PARAMETER Role
        view (default) | edit. Maps to Graph `roles = ['read']` or `['write']`.

    .PARAMETER RequireSignIn
        When set, recipients must sign in (Microsoft / guest account) to access.
        Default $true — Graph's documented secure default. Pass `-RequireSignIn:$false`
        for an anonymous-style invite gated by their email (less secure; not recommended
        for customer-facing customer-engagement packs).

    .PARAMETER SendInvitation
        When set, Graph sends an invitation email to each recipient with the share URL.
        Default $false — most operators send their own cover email out of band so the
        recipient sees Kritical-branded copy + the deliberate engagement narrative,
        not Microsoft's transactional template.

    .PARAMETER Message
        Optional custom message body included in the invitation email when -SendInvitation
        is set. Ignored when -SendInvitation is not set.

    .PARAMETER ExpirationDateTime
        Optional ISO 8601 expiry on the new permission (e.g. '2026-07-31T17:00:00Z').

    .PARAMETER Password
        Optional password gate (anonymous-style invite only).

    .PARAMETER UseDeviceCode
        Force device-code auth flow for headless contexts.

    .EXAMPLE
        Add-KriticalOneDriveShareLinkRecipients -LocalPath 'C:/Users/joshl/OneDrive - Kritical Pty Ltd/EES/EES-proposal-pack-FINAL-SHARED' -Recipients 'lincoln@eeservices.io' -Role view

        Adds Lincoln (view-access) to the EES share. Josh + Ben's existing edit
        permission stays exactly as it was.

    .EXAMPLE
        Add-KriticalOneDriveShareLinkRecipients -LocalPath $f -Recipients @('lincoln@eeservices.io','mark@eeservices.io') -Role view -SendInvitation -Message 'EES proposal pack — link arrives separately from joshua.finley@kritical.net.'

        Adds two external recipients with a Graph-sent invitation email + custom message.

    .EXAMPLE
        Add-KriticalOneDriveShareLinkRecipients -LocalPath $f -Recipients 'reviewer@external.com' -Role view -ExpirationDateTime '2026-07-31T17:00:00Z' -RequireSignIn:$false

        Adds an external reviewer with a hard expiry; sign-in not required.

    .OUTPUTS
        PSCustomObject[] — one row per newly-granted permission:
          PermissionId       [string]
          Roles              [string[]]
          GrantedToEmails    [string[]]
          GrantedToNames     [string[]]
          WebUrl             [string]   (when link-style)
          CreatedAt          [string]   ISO 8601

    .NOTES
        CONTRACT
            inputs:
              - LocalPath        : path; must exist + be under OneDrive sync root
              - Recipients       : email[]; required
              - Role             : view|edit (default view)
              - RequireSignIn    : switch (default ON via param-default-true pattern)
              - SendInvitation   : switch (default OFF)
              - Message          : optional string
              - ExpirationDateTime: optional ISO 8601
              - Password         : optional
            outputs:
              - PSCustomObject[] one per newly-granted permission
            sideEffects:
              - Connects to Microsoft Graph (Files.ReadWrite.All + Sites.ReadWrite.All)
              - Creates new share permissions on the target DriveItem
              - Optionally sends invitation email (when -SendInvitation)
              - Does NOT modify or remove existing permissions
            invariants:
              - Existing permissions on the item are untouched
              - Throws on path-outside-sync-root, item-not-found, auth-failure
              - asserts: paired tests/Unit/OneDriveShareLinkPermissions.Tests.ps1

        Author:  Joshua Finley
        Repo:    Kritical.PS.OmniFramework
        Added:   v1.1.13 — Kritical.PS.OmniFramework 2026-06-28 (.1507ab)
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword','Password',
        Justification = 'Microsoft Graph /invite contract requires a plaintext password field on the request body; converting to SecureString would force an unwrap that defeats the protection. Operator-supplied password lives in memory for the single call only.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string[]]$Recipients,
        [ValidateSet('view','edit')][string]$Role = 'view',
        # NOTE: bool (not switch) so the secure default ($true) is honoured without
        # tripping PSScriptAnalyzer's PSAvoidDefaultValueSwitchParameter rule. Pass
        # -RequireSignIn:$false explicitly to grant external-email-only access.
        [bool]$RequireSignIn = $true,
        [switch]$SendInvitation,
        [string]$Message,
        [string]$ExpirationDateTime,
        [string]$Password,
        [switch]$UseDeviceCode
    )

    $scopes = @('Files.ReadWrite.All','Sites.ReadWrite.All','User.Read')
    $resolved = Resolve-KriticalOneDriveDriveItem -LocalPath $LocalPath -Scopes $scopes -UseDeviceCode:$UseDeviceCode

    $roleString = if ($Role -eq 'edit') { 'write' } else { 'read' }
    $body = @{
        recipients     = @($Recipients | ForEach-Object { @{ email = $_ } })
        roles          = @($roleString)
        requireSignIn  = [bool]$RequireSignIn
        sendInvitation = [bool]$SendInvitation
    }
    if ($SendInvitation -and $Message) { $body.message            = $Message }
    if ($ExpirationDateTime)           { $body.expirationDateTime = $ExpirationDateTime }
    if ($Password)                     { $body.password           = $Password }

    $inviteUri = "/v1.0/me/drive/items/$($resolved.ItemId)/invite"
    $bodyJson  = $body | ConvertTo-Json -Depth 5 -Compress

    $action = "Add $($Recipients -join ', ') as $Role to $($resolved.ItemName)"
    if (-not $PSCmdlet.ShouldProcess($resolved.ItemName, $action)) { return }

    Write-Verbose "Inviting $($Recipients.Count) recipient(s) as $Role (requireSignIn=$RequireSignIn, sendInvitation=$SendInvitation)"
    $resp = Invoke-MgGraphRequest -Method POST -Uri $inviteUri -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop

    $respValue = Get-KriticalGraphProp -Object $resp -Name 'value'
    foreach ($p in @($respValue)) {
        $emails = @()
        $names  = @()
        $idV2   = Get-KriticalGraphProp -Object $p -Name 'grantedToIdentitiesV2'
        $gV2    = Get-KriticalGraphProp -Object $p -Name 'grantedToV2'
        foreach ($g in @($idV2) + @($gV2)) {
            if ($null -eq $g) { continue }
            $u = Get-KriticalGraphProp -Object $g -Name 'user'
            if ($null -eq $u) { continue }
            $em = Get-KriticalGraphProp -Object $u -Name 'email'
            $dn = Get-KriticalGraphProp -Object $u -Name 'displayName'
            if ($em) { $emails += $em }
            if ($dn) { $names  += $dn }
        }
        $link = Get-KriticalGraphProp -Object $p -Name 'link'
        [pscustomobject]@{
            PermissionId    = Get-KriticalGraphProp -Object $p -Name 'id'
            Roles           = @(Get-KriticalGraphProp -Object $p -Name 'roles')
            GrantedToEmails = $emails
            GrantedToNames  = $names
            WebUrl          = if ($link) { Get-KriticalGraphProp -Object $link -Name 'webUrl' } else { $null }
            CreatedAt       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    }
}
