# Kritical.PS.OmniFramework — Detailed Usage

```text
·· × × × ···  SirJ's Deaddrop  ··· × × × ···
---------------- A Seriously Kritical™ Production ----------------
```

Author: Joshua Finley — Kritical Pty Ltd

This file lists every exported function with the "what / why / how / proof" pattern.

---

## Foundation loader

### `Import-KriticalFoundation`

What: pulls `PSFramework` + `PSSharedGoods` + `PSWriteHTML` + `ImportExcel` (auto-installs missing). Optional Office modules (`PSWriteOffice`, `PSWriteWord`, `PSWritePDF`) auto-loaded when present.

Why: every Kritical script needs the same handful. One call, version-floored, idempotent.

How:

```powershell
Import-KriticalFoundation                                  # default
Import-KriticalFoundation -NoInstall                       # CI runner with prebaked modules
Import-KriticalFoundation -NoBanner -Quiet | Out-Null      # embedded in a larger script
Import-KriticalFoundation -MinimumVersions @{ ImportExcel='7.8.6'; PSFramework='1.11.0' }
```

Returns:

```text
Ok             : True
FailedRequired : 0
Modules        : @(@{Module=PSFramework; Status=LOADED; Version=...}, ...)
Platform       : (Get-KriticalPlatform output)
Timestamp      : 2026-06-24T...
```

### `Get-KriticalFoundationStatus`

Read-only inventory without installing/loading anything. Useful in pre-flight audit screens.

---

## Multi-OS platform

### `Get-KriticalPlatform`

Single normalised descriptor across Windows / macOS / Linux. Lookups:

- Windows: `Get-CimInstance Win32_OperatingSystem` for Caption / Version / Build / Arch.
- macOS: `sw_vers` for ProductName / ProductVersion / BuildVersion.
- Linux: `/etc/os-release` (preferred, LSB standard); falls back to `/etc/lsb-release`; `uname -r` for kernel build.

Returns:

```text
Family        : Windows | macOS | Linux | Unknown
DistroId      : windows | macos | ubuntu | debian | rhel | fedora | arch | alpine | suse | ...
DistroName    : humanised
Version       : Version
VersionString : raw
Build         : Windows build number / kernel release on *nix
Architecture  : X64 | Arm64 | X86 | Arm | Unknown
HostName      : machine name
UserName      : current user
IsAdmin       : bool
PSEdition     : Desktop | Core
PSVersion     : Version
RawProbe      : the source dict used to derive the above (for diagnostics)
```

### `Test-KriticalIsAdmin` / `Test-KriticalIsElevated`

Cross-OS privilege check. On Windows uses WindowsPrincipal; on *nix uses `id -u == 0`.

---

## Tool inventory

### `Get-KriticalToolInventory`

FHS / LSB-aware walker. Per-OS standard search paths:

- **Linux** (FHS 3.0): `/usr/local/sbin`, `/usr/local/bin`, `/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`, `/opt`, `/snap/bin`, `/var/lib/flatpak/exports/bin`, `~/.local/bin`.
- **macOS**: `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/Library/Apple/usr/bin`, `~/.local/bin`.
- **Windows**: `System32`, `WINDIR`, `ProgramFiles` (x64+x86), `WindowsApps`, `LOCALAPPDATA\Programs`, `.dotnet\tools`, Chocolatey/scoop/winget shims.

Default canonical tool list (~80 items):

- shells (pwsh, bash, zsh, sh, fish, nu)
- source control (git, gh, svn, hg)
- build/runtime (make, cmake, dotnet, msbuild, gcc, clang, node, python, ruby, go, rustc, java, mvn, gradle)
- containers/cloud (docker, podman, kubectl, helm, terraform, ansible, az, aws, gcloud, oc)
- SSH/net (ssh, curl, wget, rsync, nc, nmap, dig)
- editors (code, code-insiders, vim, nvim, emacs)
- archive/crypto (7z, tar, zip, unzip, gpg, openssl, age)
- security/hardening (hardeningkitty, lgpo, sigcheck, autoruns, procmon, accesschk)
- data (jq, yq, xmlstarlet)
- system (systemctl, journalctl, sc, wmic, reg, wevtutil, auditpol, secedit, dism, sfc)
- package mgrs (apt, dnf, yum, zypper, pacman, apk, brew, port, winget, choco, scoop)

Example:

```powershell
Get-KriticalToolInventory | Where-Object Present | Format-Table Name, FirstPath
Get-KriticalToolInventory -Tool git, docker, terraform -IncludeDuplicates | ConvertTo-Json -Depth 5
```

### `Find-KriticalTool` / `Test-KriticalToolPresent`

Per-tool match lookup. `Find-KriticalTool` returns every match (so duplicates surface); `Test-KriticalToolPresent` is the boolean.

---

## Logging

### `Write-KriticalLog`

```powershell
Start-KriticalLogSession                                       # PSFramework when loaded; plain JSONL fallback
Write-KriticalLog -Level Info -Message 'Phase 1 starting' -Tag 'krit-omni','phase-1'
Write-KriticalLog -Level Error -Message 'connection failed' -Data @{ host = 'foo'; port = 443 }
Stop-KriticalLogSession
```

Logs land at `%LOCALAPPDATA%\Kritical\Logs\krit-<utc>.jsonl` (fallback) or in PSFramework's configured log path.

---

## Reporting

### `New-KriticalHtmlReport`

Branded HTML with the Kritical banner at the top, per-section tables (PSWriteHTML when present; minimal hand-rolled HTML otherwise).

```powershell
$inv = Get-KriticalToolInventory
$plat = Get-KriticalPlatform
New-KriticalHtmlReport `
    -Title 'Operator Day-1 Audit' `
    -Subtitle 'Tool inventory + platform descriptor' `
    -Section @{ Tools = $inv; Platform = @($plat) } `
    -OutFile C:\drop\day1-audit.html
```

### `New-KriticalExcelReport`

Multi-sheet xlsx with the Kritical brand banner as sheet 1.

```powershell
New-KriticalExcelReport `
    -Title 'Operator Day-1 Audit' `
    -Sheet @{ Tools = $inv; Platform = @($plat) } `
    -OutFile C:\drop\day1-audit.xlsx
```

---

## Config + path resolution

### `Resolve-KriticalRepoRoot` / `Get-KriticalConfig` / `Get-KriticalProject` / `Get-KriticalPath`

Same idea as the old `Pax8FrameworkConfig`, now under the Krit.* namespace and OmniFramework-bundled. Resolves `krit-project.json` (preferred) or legacy `pax8-framework.settings.json` upward from the cwd.

```powershell
$root  = Resolve-KriticalRepoRoot
$cfg   = Get-KriticalConfig            # full PSCustomObject including config + repo root
$proj  = Get-KriticalProject -Name 'pax8-connector'
$lpath = Get-KriticalPath    -Name 'analysis'
```

---

## Secrets posture

### `Test-KriticalSecretsLoaded`

Read-only check that the canonical Kritical secrets folder is reachable and required files are present.

```powershell
Test-KriticalSecretsLoaded -RequireFiles 'pax8-mcpServer-auth.txt','psgallery-api-key.txt' |
    Format-List Ok, FolderPresent, MissingFiles
```

---

## Proof it works

```powershell
Import-Module Kritical.PS.OmniFramework -Force
Get-KriticalPlatform | Format-List
(Get-KriticalToolInventory | Where-Object Present).Count
Test-KriticalSecretsLoaded
.\tests\Invoke-AllTests.ps1   # 17/17 expected
```

---

## References

| # | Title | URL |
|---|---|---|
| 1 | PSFramework | <https://github.com/PowershellFrameworkCollective/psframework> |
| 2 | PSSharedGoods | <https://github.com/EvotecIT/PSSharedGoods> |
| 3 | PSWriteHTML | <https://github.com/EvotecIT/PSWriteHTML> |
| 4 | ImportExcel | <https://github.com/dfinke/ImportExcel> |
| 5 | PSWriteOffice / PSWriteWord / PSWritePDF | <https://github.com/EvotecIT/PSWriteOffice> |
| 6 | Filesystem Hierarchy Standard | <https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html> |
| 7 | Linux Standard Base | <https://refspecs.linuxfoundation.org/lsb.shtml> |
| 8 | os-release(5) | <https://www.freedesktop.org/software/systemd/man/os-release.html> |
