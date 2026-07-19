# [PS-MODULE] Kritical.PS.OmniFramework — README (human)

> The **multi-OS PowerShell foundation** every other Kritical PS package stands on.
> One `Import-Module` gives you structured logging, cross-platform OS/distro/arch
> detection, an FHS/LSB-aware tool-inventory walker, branded HTML/Excel/PDF/DOCX
> reporting, config/path resolution, and a Microsoft Graph OneDrive share-link helper.

| | |
|---|---|
| **Module** | `Kritical.PS.OmniFramework` |
| **Version** | 1.1.14 |
| **Requires** | PowerShell **5.1+** — `Desktop` **and** `Core` editions (Windows / macOS / Linux) |
| **Public surface** | **30 functions** (grouped below) |
| **Role** | Foundation — sits **under** `Kritical.PS.Hardening` and every other Kritical PS module |
| **External deps** | PSFramework, PSSharedGoods, PSWriteHTML, ImportExcel (+ optional PSWriteOffice) |
| **Author** | Joshua Finley · (c) 2026 Kritical Pty Ltd |

---

## The load-order design decision (why `RequiredModules` is empty)

This is the module's most important architectural fact. As of **1.0.2**, PSFramework et al.
were **removed from `RequiredModules`** and are instead **soft-imported at use time** via
`Import-KriticalFoundation`, and declared in `ExternalModuleDependencies` so PSGallery
still pulls them transitively.

**Why:** PowerShell hard-imports `RequiredModules` *before* the consuming `.psm1` runs.
If a stale PSFramework (e.g. an older 1.0.0.1 from a transient dependency) was already
loaded in the session, `Import-Module Kritical.PS.OmniFramework` — and everything
depending on it — failed with *"Assembly with same name is already loaded"* (an AppDomain
collision). The soft-import path detects an already-loaded PSFramework at **any** version
and reuses it rather than force-upgrading, and `Write-KriticalLog` degrades gracefully to
JSONL when PSFramework is missing entirely. This is what keeps the whole Kritical PS stack
importable in a dirty session.

## Function map (30 public)

### 1. Foundation loader
| Function | Does |
|---|---|
| `Import-KriticalFoundation` | Soft-imports PSFramework + PSSharedGoods + PSWriteHTML + ImportExcel in one call (version-collision-safe). |
| `Get-KriticalFoundationStatus` | Reports which foundation modules are loaded and at what version. |

### 2. Platform / OS detection (multi-OS)
| Function | Does |
|---|---|
| `Get-KriticalPlatform` | OS + distro + architecture + privilege across Windows/macOS/Linux. |
| `Test-KriticalIsAdmin` / `Test-KriticalIsElevated` | Privilege checks. |

### 3. Tool inventory (FHS/LSB-aware)
| Function | Does |
|---|---|
| `Get-KriticalToolInventory` | Walks every standard tool path per OS (FHS/LSB-aware). |
| `Find-KriticalTool` / `Test-KriticalToolPresent` | Locate / assert a specific tool. |

### 4. Structured logging (PSFramework-backed)
| Function | Does |
|---|---|
| `Write-KriticalLog` | Structured log with JSON + App Insights sinks; degrades to JSONL if PSFramework absent. |
| `Start-KriticalLogSession` / `Stop-KriticalLogSession` | Session lifecycle. |

### 5. Branded reporting & documents
| Function | Does |
|---|---|
| `New-KriticalHtmlReport` | Branded HTML report (auto-creates parent dir). |
| `New-KriticalExcelReport` | Branded Excel report. |
| `Get-KriticalBrandSpec` | Loads canonical `brand-spec.json` (colours #13365C/#15AFD1, Roboto/Assistant fonts, logo/template paths) with per-session caching — single source of truth. |
| `New-KriticalBrandedDocument` | Renders Markdown/HTML → branded PDF/DOCX/HTML in one call (Pandoc+wkhtmltopdf preferred, Chrome/Edge headless fallback; DOCX via Pandoc `--reference-doc`). |

### 6. Banner
| Function | Does |
|---|---|
| `Write-KriticalBanner` / `Get-KriticalBanner` | Canonical Kritical brand banner. |

### 7. Config + path resolution (from Pax8FrameworkConfig)
| Function | Does |
|---|---|
| `Resolve-KriticalRepoRoot` · `Get-KriticalConfig` · `Get-KriticalProject` · `Get-KriticalPath` | Repo-root + config + project + path resolution. |

### 8. Secrets posture (read-only)
| Function | Does |
|---|---|
| `Test-KriticalSecretsLoaded` | Read-only secrets-presence check. |

### 9. Markdown linter (1.1.8)
| Function | Does |
|---|---|
| `Invoke-KriticalMdLint` | Programmatic Markdown linter. |

### 10. OneDrive share-link helper (Microsoft Graph delegated, 1.1.12–1.1.13)
| Function | Does |
|---|---|
| `New-KriticalOneDriveShareLink` | Create a share link (preferred over heavy email attachments for customer-pack delivery). |
| `Get-KriticalOneDriveShareLinkPermissions` | List current grants. |
| `Add-KriticalOneDriveShareLinkRecipients` | Add recipients without disrupting existing shares. |
| `Remove-KriticalOneDriveShareLinkPermission` | Revoke specific recipients. |
| `Set-KriticalOneDriveShareLinkPermission` | Change role/expiry/password in place. |

> **File-name note:** some public functions are grouped per source file — e.g.
> `New-KriticalReport.ps1` backs the Html/Excel report pair and `Resolve-KriticalConfig.ps1`
> backs the config/path family — so the 18 `Public/*.ps1` files export the 30 manifest functions.

## Estate role & test-coverage flag

- **Foundation dependency:** `Kritical.PS.GitHub`, the Lens family, and `Kritical.PS.Hardening`
  all `dependsOn` / import this. A regression here cascades estate-wide — which is exactly
  why the **L6 PS-TEST-COVERAGE-MAP ranked this the #1 zero-test-coverage priority** (the live
  repo ships a `tests/` dir but no first-party `.Tests.ps1` was detected; only the read-only
  `Krit.ModernVCheck` snapshot carries its tests). First test target: `Import-KriticalFoundation`
  version-collision path + `Get-KriticalPlatform` per-OS branches.

## Repo layout

```
src/Kritical.PS.OmniFramework.psd1   manifest v1.1.14 (30 exports; RequiredModules deliberately empty)
src/Kritical.PS.OmniFramework.psm1   loader
src/Public/*.ps1                     18 files → 30 exported functions
src/Private/_Banner.ps1              banner internals
src/Private/_KritOneDriveResolver.ps1  Graph OneDrive resolution
src/Assets/kritical-logo.txt         ASCII banner asset
tests/                               Pester unit + e2e (see L6 note)
tools/ · scripts/ · docs/            supporting
Kritical.PS.OmniFramework-1.0.2.zip / -1.1.14.zip   packaged releases
```

## Family relationships

- **Stands under:** `Kritical.PS.Hardening` + every Kritical PS package.
- **Consumed by:** `Kritical.PS.GitHub` (`Import-KritGitHubFoundation` wires it), the Lens family.
- **Brand source:** `Get-KriticalBrandSpec` reads the canonical brand-spec; asset inventory at
  `KRTPax8ToShopifyConnector/reference/KRITICAL-BRAND-ASSET-INVENTORY-1507.md`.

---

*Companion machine doc: `README-AI.md` (schema `kritical-readme-ai/v1`). Generated from
live manifest (incl. release notes) + public source tree — new file, does not touch `README.md`.*
