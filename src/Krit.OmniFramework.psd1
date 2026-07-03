@{
    RootModule        = 'Krit.OmniFramework.psm1'
    ModuleVersion     = '1.1.14'
    GUID              = 'b3d1f5c9-7a4e-4c8b-9e2f-1a7c3b8d2e4f'
    Author            = 'Joshua Finley'
    CompanyName       = 'Kritical Pty Ltd'
    Copyright         = '(c) 2026 Kritical Pty Ltd. All rights reserved.'
    Description       = 'Kritical OmniFramework — multi-OS PowerShell foundation. One Import-Module call gives you: structured logging (PSFramework), shared utilities (PSSharedGoods, disambiguated from psutil), HTML reporting (PSWriteHTML), Office/Word/PDF output (PSWriteOffice), Excel I/O (ImportExcel), OS+distro+architecture detection across Windows/macOS/Linux, FHS/LSB-aware tool-inventory walker, and Kritical-branded report templates. Built to stand under Kritical.PS.Hardening and every other Kritical PowerShell package.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop','Core')

    # 1.0.2 — RequiredModules removed (was the cause of PSFramework AppDomain
    # version-collision failures: PowerShell hard-imports RequiredModules BEFORE
    # the psm1 runs, so a stale PSFramework already loaded in the session blew
    # up Import-Module Krit.OmniFramework with "Assembly with same name is
    # already loaded"). Soft-imported via Import-KritFoundation at use time
    # instead; declared in ExternalModuleDependencies below so Install-Module
    # STILL pulls them transitively on PSGallery install.
    # PSWriteOffice ships PSWriteWord/Excel/PowerPoint via separate modules in some versions; treat as optional.

    FunctionsToExport = @(
        # Banner
        'Write-KritBanner', 'Get-KritBanner',
        # Platform / OS detection
        'Get-KritPlatform', 'Test-KritIsAdmin', 'Test-KritIsElevated',
        # Tool inventory (multi-OS, FHS/LSB-aware)
        'Get-KritToolInventory', 'Find-KritTool', 'Test-KritToolPresent',
        # Foundation loader
        'Import-KritFoundation', 'Get-KritFoundationStatus',
        # Structured logging (PSFramework-backed)
        'Write-KritLog', 'Start-KritLogSession', 'Stop-KritLogSession',
        # Branded reporting
        'New-KritHtmlReport', 'New-KritExcelReport',
        # Config + path resolution (carried forward from Pax8FrameworkConfig)
        'Resolve-KritRepoRoot', 'Get-KritConfig', 'Get-KritProject', 'Get-KritPath',
        # Secrets posture (read-only)
        'Test-KritSecretsLoaded',
        # 1.1.0 - Brand pipeline
        'Get-KritBrandSpec',
        'New-KritBrandedDocument',
        # 1.1.8 - Programmatic markdown linter
        'Invoke-KritMdLint',
        # 1.1.12 - OneDrive sharing-link helper (Microsoft Graph delegated auth)
        # Born from EES proposal-pack distribution 2026-06-28: prefer OneDrive share links
        # over heavy email attachments for customer-facing pack delivery.
        'New-KritOneDriveShareLink',
        # 1.1.13 - OneDrive share-permission management (Get / Add / Remove / Set)
        # Operator-controlled rotation of who has access to a customer-pack folder:
        # add recipients without disrupting existing shares, list current grants,
        # revoke specific recipients, change roles/expiry/password in place.
        'Get-KritOneDriveShareLinkPermissions',
        'Add-KritOneDriveShareLinkRecipients',
        'Remove-KritOneDriveShareLinkPermission',
        'Set-KritOneDriveShareLinkPermission'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Kritical','OmniFramework','Framework','PSFramework','PSSharedGoods','PSWriteHTML','PSWriteOffice','ImportExcel','MultiOS','CrossPlatform','OSDetect','Hardening','MSP','Automation')
            LicenseUri   = 'https://kritical.net/legal/license'
            ProjectUri   = 'https://github.com/Sir-J-AU/Krit.OmniFramework'
            IconUri      = 'https://kritical.net/assets/horizontal_logo.png'
            ExternalModuleDependencies = @('PSFramework','PSSharedGoods','PSWriteHTML','ImportExcel')
            ReleaseNotes = @'
1.1.0 - Brand pipeline.
  * NEW Get-KritBrandSpec - loads canonical brand-spec.json (colours, fonts,
    corporate identity, contact details, logo paths, template paths) with
    per-session caching + resolution-order fallbacks. Single source of truth
    for every Kritical-branded artefact.
  * NEW New-KritBrandedDocument - renders Markdown (or HTML) source to
    Kritical-branded PDF / DOCX / HTML in one call. Pulls brand spec from
    Get-KritBrandSpec. Applies primary #13365C + secondary #15AFD1 + Roboto
    headings + Assistant body. Inserts Horizontal_Logo.png header + ABN/ACN/
    address/tagline footer. Optional Outlook email-signature append.
    Engines: Pandoc + wkhtmltopdf (preferred) / Chrome+Edge headless
    (fallback). DOCX uses Pandoc --reference-doc against Huzaifa's
    Kritical-BaseTemplate-CURRENT.docx.
  * Brand inventory + asset locations documented at
    Github/KRTPax8ToShopifyConnector/reference/KRITICAL-BRAND-ASSET-INVENTORY-1507.md

1.0.2 - Resilience fix (PSFramework AppDomain collision).
  * Removed PSFramework/PSSharedGoods/PSWriteHTML/ImportExcel from
    RequiredModules. PowerShell hard-imports RequiredModules BEFORE the
    consuming module's psm1 runs, so any stale PSFramework already loaded
    in the session (e.g. an older PSFramework 1.0.0.1 from a transient
    dependency) caused Import-Module Krit.OmniFramework — and everything
    that depends on it (Kritical.PS.Hardening) — to fail with "Assembly with same
    name is already loaded".
  * Dependencies are now declared in ExternalModuleDependencies (PSData)
    so Install-Module Krit.OmniFramework STILL pulls them transitively on
    fresh PSGallery installs.
  * Import-KritFoundation now detects already-loaded PSFramework at ANY
    version and reuses it instead of force-upgrading, so Write-KritLog +
    everything downstream keeps working even when the AppDomain is
    locked to an older version.
  * Write-KritLog continues to degrade gracefully to JSONL when
    PSFramework is missing.

1.0.1 - Bug fix.
  * New-KritHtmlReport now auto-creates the parent directory of -OutFile
    before calling PSWriteHTML's Save-HTML (which would otherwise fall back
    to %TEMP% and emit a warning).

1.0.0 — Initial release.
  * Multi-OS platform detection (Windows / macOS / Linux + distro + arch + privilege).
  * FHS/LSB-aware tool inventory (Get-KritToolInventory walks every standard path per OS).
  * Foundation loader (Import-KritFoundation pulls PSFramework + PSSharedGoods + PSWriteHTML + ImportExcel in one call).
  * Structured logging via PSFramework (Write-KritLog with JSON + Application Insights sinks).
  * Branded HTML + Excel reports (New-KritHtmlReport / New-KritExcelReport) with the canonical Kritical banner embedded.
  * Repo-root + config resolution carried forward from the original Pax8FrameworkConfig.
  * Pester unit + e2e test suite.
  * Joshua Finley, Kritical Pty Ltd.
'@
        }
    }
}
