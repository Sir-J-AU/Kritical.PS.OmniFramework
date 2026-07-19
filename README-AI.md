{
  "schema": "kritical-readme-ai/v1",
  "generatedUtc": "2026-07-16",
  "generatedFrom": ["src/Kritical.PS.OmniFramework.psd1 (incl ReleaseNotes)", "src/Public/*.ps1", "src/Private/*.ps1"],
  "repo": {
    "name": "Kritical.PS.OmniFramework",
    "version": "1.1.14",
    "guid": "b3d1f5c9-7a4e-4c8b-9e2f-1a7c3b8d2e4f",
    "family": "Kritical.PS",
    "author": "Joshua Finley",
    "company": "Kritical Pty Ltd",
    "requiresPowerShell": "5.1",
    "compatibleEditions": ["Desktop", "Core"],
    "multiOS": ["Windows", "macOS", "Linux"],
    "role": "foundation — stands under Kritical.PS.Hardening and every other Kritical PS package",
    "purpose": "Multi-OS PowerShell foundation: one Import-Module gives structured logging (PSFramework), shared utils (PSSharedGoods), HTML/Excel/PDF/DOCX branded reporting (PSWriteHTML/ImportExcel/PSWriteOffice), OS/distro/arch detection, FHS/LSB-aware tool inventory, config/path resolution, and a Microsoft Graph OneDrive share-link helper.",
    "externalModuleDependencies": ["PSFramework", "PSSharedGoods", "PSWriteHTML", "ImportExcel"],
    "optionalDeps": ["PSWriteOffice (PSWriteWord/Excel/PowerPoint)"],
    "tags": ["Kritical", "OmniFramework", "Framework", "PSFramework", "MultiOS", "CrossPlatform", "OSDetect", "Hardening", "MSP", "Automation"]
  },
  "keyDesignDecision": {
    "name": "RequiredModules deliberately empty (AppDomain-collision fix, v1.0.2)",
    "problem": "PowerShell hard-imports RequiredModules BEFORE the psm1 runs; a stale PSFramework already loaded in-session caused Import-Module to fail with 'Assembly with same name is already loaded', taking down everything downstream (Kritical.PS.Hardening).",
    "solution": "Soft-import deps at use time via Import-KriticalFoundation; declare in ExternalModuleDependencies so Install-Module still pulls transitively. Import-KriticalFoundation reuses an already-loaded PSFramework at ANY version instead of force-upgrading. Write-KriticalLog degrades to JSONL when PSFramework is absent."
  },
  "publicApiGroups": {
    "foundation-loader": [
      { "name": "Import-KriticalFoundation", "does": "soft-import PSFramework+PSSharedGoods+PSWriteHTML+ImportExcel, version-collision-safe" },
      { "name": "Get-KriticalFoundationStatus", "does": "report loaded foundation modules + versions" }
    ],
    "platform-detection": [
      { "name": "Get-KriticalPlatform", "does": "OS+distro+arch+privilege across Win/macOS/Linux" },
      { "name": "Test-KriticalIsAdmin", "does": "admin check" },
      { "name": "Test-KriticalIsElevated", "does": "elevation check" }
    ],
    "tool-inventory": [
      { "name": "Get-KriticalToolInventory", "does": "walk every standard tool path per OS (FHS/LSB-aware)" },
      { "name": "Find-KriticalTool", "does": "locate a specific tool" },
      { "name": "Test-KriticalToolPresent", "does": "assert a tool present" }
    ],
    "structured-logging": [
      { "name": "Write-KriticalLog", "does": "structured log, JSON + App Insights sinks, degrades to JSONL" },
      { "name": "Start-KriticalLogSession", "does": "begin log session" },
      { "name": "Stop-KriticalLogSession", "does": "end log session" }
    ],
    "branded-reporting": [
      { "name": "New-KriticalHtmlReport", "does": "branded HTML report, auto-creates parent dir (1.0.1 fix)" },
      { "name": "New-KriticalExcelReport", "does": "branded Excel report" },
      { "name": "Get-KriticalBrandSpec", "does": "load canonical brand-spec.json (colours #13365C/#15AFD1, Roboto/Assistant fonts, logo/template paths), per-session cached — single source of truth" },
      { "name": "New-KriticalBrandedDocument", "does": "render Markdown/HTML -> branded PDF/DOCX/HTML; Pandoc+wkhtmltopdf preferred, Chrome/Edge headless fallback; DOCX via Pandoc --reference-doc" }
    ],
    "banner": [
      { "name": "Write-KriticalBanner", "does": "emit brand banner" },
      { "name": "Get-KriticalBanner", "does": "return brand banner" }
    ],
    "config-path-resolution": [
      { "name": "Resolve-KriticalRepoRoot", "does": "resolve repo root" },
      { "name": "Get-KriticalConfig", "does": "get config" },
      { "name": "Get-KriticalProject", "does": "get project" },
      { "name": "Get-KriticalPath", "does": "resolve path" }
    ],
    "secrets": [
      { "name": "Test-KriticalSecretsLoaded", "does": "read-only secrets-presence check" }
    ],
    "markdown-lint": [
      { "name": "Invoke-KriticalMdLint", "does": "programmatic Markdown linter (1.1.8)" }
    ],
    "onedrive-sharelink-graph": [
      { "name": "New-KriticalOneDriveShareLink", "does": "create share link (customer-pack delivery, 1.1.12)" },
      { "name": "Get-KriticalOneDriveShareLinkPermissions", "does": "list current grants" },
      { "name": "Add-KriticalOneDriveShareLinkRecipients", "does": "add recipients without disrupting existing shares" },
      { "name": "Remove-KriticalOneDriveShareLinkPermission", "does": "revoke specific recipients" },
      { "name": "Set-KriticalOneDriveShareLinkPermission", "does": "change role/expiry/password in place" }
    ]
  },
  "privateApi": [
    { "name": "_Banner", "file": "src/Private/_Banner.ps1", "role": "banner internals" },
    { "name": "_KritOneDriveResolver", "file": "src/Private/_KritOneDriveResolver.ps1", "role": "Graph OneDrive resolution" }
  ],
  "exportCount": 30,
  "publicFileCount": 18,
  "fileToFunctionNote": "18 Public/*.ps1 files export 30 manifest functions (report pair backed by New-KriticalReport.ps1; config/path family by Resolve-KriticalConfig.ps1).",
  "estateRole": {
    "standsUnder": ["Kritical.PS.Hardening", "all Kritical PS packages"],
    "consumedBy": ["Kritical.PS.GitHub (Import-KritGitHubFoundation)", "Lens family"],
    "brandAssetInventory": "KRTPax8ToShopifyConnector/reference/KRITICAL-BRAND-ASSET-INVENTORY-1507.md"
  },
  "testCoverage": {
    "l6Rank": "Tier 1 #1 zero-test-coverage priority",
    "note": "ships tests/ dir but no first-party .Tests.ps1 detected in live repo; only the read-only Krit.ModernVCheck snapshot carries its tests. First target: Import-KriticalFoundation collision path + Get-KriticalPlatform per-OS branches."
  },
  "provenance": {
    "note": "Generated from live manifest (incl release notes) + public source tree. New files only (README-HUMAN.md + README-AI.md); README.md not touched.",
    "lane": "L4 (NIGHT-SHIFT-WORKLIST)",
    "repoOrdinal": "7th repo in L4 sweep; also L6 Tier-1 #1 test-gap target"
  }
}
