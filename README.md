# Krit.OmniFramework — Kritical multi-OS PowerShell Foundation

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
      — If you found this, you were meant to —

---------------- A Seriously Kritical™ Production ----------------

                                   [] →
                 (¯`·.¸¸.·´¯)
               .·´            `·.        [] →
               `·.______________.·´
              |   +------------------+   |
              |   |     Kritical™     |  |
              |   |   []      []      |  |
              |   |                  |  |
              |   |   []  []  []     |  |
              |   +------------------+   |
                  (._.·´¯`·.¸_)

                     Your last call.
                   And your first move.

                         ★  ☆  ★

                     +61 1300 274 655
                 sales at kritical dot net

-----------------------------------------------------------------
```

**Author**: Joshua Finley — Kritical Pty Ltd — <https://kritical.net>
**License**: see [LICENSE](./LICENSE)
**Version**: 1.0.0

---

## What this is

One `Import-Module` brings up the Kritical PowerShell foundation:

| Layer | Provided by | What you get |
| --- | --- | --- |
| **Structured logging** | PSFramework | `Write-KritLog` with JSON output + Application Insights sink option |
| **Shared utilities** | PSSharedGoods (disambiguated from `psutil`) | every Evotec helper your script ever needs |
| **HTML reporting** | PSWriteHTML | `New-KritHtmlReport` — Kritical-branded HTML with banner header |
| **Excel I/O** | ImportExcel | `New-KritExcelReport` — multi-sheet xlsx with the Kritical brand sheet |
| **Office output** *(optional)* | PSWriteOffice / PSWriteWord / PSWritePDF | auto-imported when present |
| **Multi-OS detection** | built-in `Get-KritPlatform` | one PSCustomObject across Windows / macOS / Linux + distro + arch + privilege |
| **FHS/LSB tool inventory** | built-in `Get-KritToolInventory` | walks every standard search path per OS, reports presence + duplicates |
| **Branding** | built-in | canonical Kritical banner loaded from `OneDrive\Kritical-Branding\public\KriticalLogo.txt` with bundled fallback |
| **OneDrive share-link toolkit** *(v1.1.12+)* | Microsoft Graph (delegated user-auth — no API keys) | `New-/Get-/Add-/Set-/Remove-KritOneDriveShareLink*` — mint, audit, add to, modify and revoke OneDrive for Business share permissions from PowerShell. Distribute multi-document packs by share link instead of 10MB email attachment. See [docs/OneDrive-Share-Link-Toolkit.md](docs/OneDrive-Share-Link-Toolkit.md). |
| **Config + path resolution** | built-in | `Resolve-KritRepoRoot` / `Get-KritConfig` / `Get-KritProject` / `Get-KritPath` |
| **Secrets posture (read-only)** | built-in | `Test-KritSecretsLoaded` |

This module is the foundation under [`Krit.Pax8Mcp`](https://github.com/Sir-J-AU/Krit.Pax8Mcp), [`Kritical.PS.Hardening`](https://github.com/Sir-J-AU/Kritical.PS.Hardening), and every other Kritical operator / customer script.

---

## Install

### Option A — PSGallery

```powershell
Install-Module Krit.OmniFramework -Scope CurrentUser
Import-Module  Krit.OmniFramework -Force
Import-KritFoundation     # one call loads PSFramework + PSSharedGoods + PSWriteHTML + ImportExcel
```

### Option B — GitHub release zip

```powershell
gh release download v1.0.0 -R Sir-J-AU/Krit.OmniFramework -p '*.zip' -D $env:TEMP --clobber
$psMod = ($env:PSModulePath -split ';' | Where-Object { $_ -match 'Documents\\PowerShell\\Modules$' } | Select-Object -First 1)
$instDir = Join-Path $psMod 'Krit.OmniFramework\1.0.0'
Expand-Archive -LiteralPath "$env:TEMP\Krit.OmniFramework-1.0.0.zip" -DestinationPath $instDir -Force
Import-Module Krit.OmniFramework -Force
```

---

## Quickstart

```powershell
Import-Module Krit.OmniFramework -Force
Import-KritFoundation                       # pulls all required modules, branded report

# Multi-OS detection
Get-KritPlatform | Format-List

# Tool inventory across LSB/FHS standard paths
Get-KritToolInventory | Where-Object Present | Format-Table Name, FirstPath

# Branded HTML report
$inv = Get-KritToolInventory
New-KritHtmlReport -Title 'Operator Tool Inventory' -Section @{ Tools = $inv } -OutFile C:\drop\inv.html

# Branded Excel report (multi-sheet, Kritical-banner sheet auto-added)
New-KritExcelReport -Title 'Operator Tool Inventory' -Sheet @{ Tools = $inv } -OutFile C:\drop\inv.xlsx

# Structured logging (PSFramework when loaded, plain JSONL fallback otherwise)
Start-KritLogSession
Write-KritLog -Level Info -Message 'Hello from Krit.OmniFramework' -Tag 'demo'
```

---

## Why this exists (the design points)

- **Stop re-deriving the foundation per script.** Every Kritical operator script needs the same handful of OSS modules; this module locks the version floors + import order in one place.
- **Stop guessing the OS.** `Get-KritPlatform` returns a single normalised descriptor; downstream code branches on object properties rather than scattering `$IsLinux`/`$IsMacOS`/`$IsWindows` checks.
- **Standardise on PSSharedGoods, not psutil.** PSGallery has both names floating around; Kritical uses Evotec's PSSharedGoods (active, ~290+ utilities). Avoid confusion with the Python `psutil` library.
- **Multi-OS tool inventory** — every Kritical operator machine answers `which-do-I-have-installed` the same way, regardless of OS. Linux uses FHS/LSB standard paths; macOS adds Homebrew + MacPorts; Windows adds winget/choco/scoop shims.
- **Kritical brand discipline** — every public-facing artefact (HTML report, Excel export, console output) starts with the canonical Kritical banner loaded from the central branding folder.

---

## Exported functions

| Function | Purpose |
| --- | --- |
| `Import-KritFoundation` | Pull PSFramework + PSSharedGoods + PSWriteHTML + ImportExcel in one call. Optional Office modules auto-load when present. Auto-installs missing required modules to CurrentUser scope (override with `-NoInstall`). |
| `Get-KritFoundationStatus` | Read-only inventory of what's installed / loaded. |
| `Get-KritPlatform` | Normalised multi-OS descriptor (Family / DistroId / Version / Architecture / IsAdmin / PSVersion / etc.). |
| `Test-KritIsAdmin` / `Test-KritIsElevated` | Cross-OS privilege check. |
| `Get-KritToolInventory` | FHS/LSB-aware tool inventory across every standard search path per OS. Default canonical list of ~80 tools; pass `-Tool` to scope. |
| `Find-KritTool` | Returns every match for a tool name across standard paths (so you can spot duplicates). |
| `Test-KritToolPresent` | Boolean version. |
| `Write-KritLog` / `Start-KritLogSession` / `Stop-KritLogSession` | Structured logger; PSFramework-backed when loaded, plain JSONL fallback otherwise. |
| `New-KritHtmlReport` | Kritical-branded HTML report (PSWriteHTML primary, minimal hand-rolled HTML fallback). |
| `New-KritExcelReport` | Kritical-branded xlsx (multi-sheet, banner sheet auto-added; uses ImportExcel). |
| `Resolve-KritRepoRoot` | Walks up to the first Kritical-repo marker (`.git` / `krit-project.json` / `CLAUDE.md`). |
| `Get-KritConfig` / `Get-KritProject` / `Get-KritPath` | Config-driven access to project + path nodes from `krit-project.json`. |
| `Test-KritSecretsLoaded` | Read-only check that the canonical Kritical secrets folder + named files are present. |
| `Get-KritBanner` / `Write-KritBanner` | Canonical brand banner readers. |

---

## Tests

```powershell
cd "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Krit.OmniFramework"
.\tests\Invoke-AllTests.ps1
```

17 Pester unit tests across Banner / Platform / ToolInventory / Foundation / Report. Test artefacts land at `%LOCALAPPDATA%\Kritical\Krit.OmniFramework\test-output\` (out of repo).

---

## Files

```text
Krit.OmniFramework/
├── README.md / LICENSE / CONTRIBUTING.md
├── docs/ (USAGE / ARCHITECTURE / PUBLISHING)
├── src/
│   ├── Krit.OmniFramework.psd1                ← Author=Joshua Finley
│   ├── Krit.OmniFramework.psm1
│   ├── Assets/kritical-logo.txt               ← bundled brand banner fallback
│   ├── Private/_Banner.ps1
│   └── Public/
│       ├── Get-KritPlatform.ps1
│       ├── Get-KritToolInventory.ps1
│       ├── Import-KritFoundation.ps1
│       ├── Write-KritLog.ps1
│       ├── New-KritReport.ps1
│       └── Resolve-KritConfig.ps1
├── tests/
│   ├── Invoke-AllTests.ps1
│   └── Unit/ (Banner / Platform / ToolInventory / Foundation / Report)
└── tools/Publish-KritOmniFramework.ps1
```

---

## Related Kritical packages

- **`Krit.Pax8Mcp`** — Pax8 hosted MCP wiring for Claude Code / Codex / Cursor / VS Code. <https://github.com/Sir-J-AU/Krit.Pax8Mcp>
- **`Kritical.PS.Hardening`** — Windows hardening audit built on this foundation, wrapping HotCakeX Harden-Windows-Security-Module, HardeningKitty, and the Microsoft Security Compliance Toolkit. <https://github.com/Sir-J-AU/Kritical.PS.Hardening>
- **`Kritical-Pax8API`** — headless Pax8 partner-API PowerShell client.

---

## Support

- Hotline: +61 1300 274 655
- Email: sales at kritical dot net
- Web: <https://kritical.net>
