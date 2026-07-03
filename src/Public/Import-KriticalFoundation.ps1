function Import-KriticalFoundation {
    <#
    .SYNOPSIS
        Loads the Kritical PowerShell foundation: PSFramework + PSSharedGoods +
        PSWriteHTML + ImportExcel + optional PSWriteOffice/PSWriteWord/PSWritePDF.
        Auto-installs missing deps (CurrentUser scope) unless -NoInstall.

    .DESCRIPTION
        Foundation discipline: every Kritical script that needs logging /
        reporting / Excel I/O can call `Import-KriticalFoundation` at the top
        instead of remembering the half-dozen Install-Module + Import-Module
        incantations. Returns a status object for the caller.

        Why PSSharedGoods (not psutil): there are TWO competing modules in
        the PSGallery namespace — Evotec/PSSharedGoods (active, ~290+ utils,
        Kritical-canonical) and a stale "psutil" sometimes confused with the
        Python library. We standardise on PSSharedGoods to remove ambiguity.

    .PARAMETER NoInstall
        Skip Install-Module attempts for missing deps. Useful in CI where
        the runner has them pre-installed.

    .PARAMETER MinimumVersions
        Optional hashtable overriding the default minimum-version floors.

    .EXAMPLE
        Import-KriticalFoundation

    .EXAMPLE
        # Quiet mode in a script
        Import-KriticalFoundation -NoBanner | Out-Null

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [hashtable] $MinimumVersions,
        [switch]    $NoInstall,
        [switch]    $NoBanner,
        [switch]    $Quiet
    )

    if (-not $NoBanner.IsPresent) { Write-KriticalBanner -Title 'Import-KriticalFoundation' -Compact }

    $defaultMin = @{
        'PSFramework'    = '1.10.318'
        'PSSharedGoods'  = '0.0.290'
        'PSWriteHTML'    = '1.27.0'
        'ImportExcel'    = '7.8.6'
    }
    $optionalModules = @('PSWriteOffice','PSWriteWord','PSWritePDF')
    if ($MinimumVersions) {
        foreach ($k in $MinimumVersions.Keys) { $defaultMin[$k] = [string]$MinimumVersions[$k] }
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    function Add-Row { param($name,$status,$version,$detail)
        $results.Add([pscustomobject]@{ Module=$name; Status=$status; Version=$version; Detail=$detail })
    }

    foreach ($mod in $defaultMin.Keys) {
        $needed = [Version]$defaultMin[$mod]

        # 1.0.2 — AppDomain-collision soft-handling. If the module is ALREADY
        # loaded in this session at ANY version, reuse it. Force-Import to a
        # different version would fail with "Assembly with same name is
        # already loaded" on modules like PSFramework that ship their own .NET DLL.
        $alreadyLoaded = Get-Module -Name $mod -ErrorAction SilentlyContinue
        if ($alreadyLoaded) {
            $alreadyLoaded = $alreadyLoaded | Sort-Object Version -Descending | Select-Object -First 1
            if ($alreadyLoaded.Version -lt $needed) {
                Add-Row $mod 'LOADED-OLDER' $alreadyLoaded.Version ("session has $($alreadyLoaded.Version); >= $needed preferred but cannot upgrade in-place (restart pwsh to refresh)")
            } else {
                Add-Row $mod 'LOADED' $alreadyLoaded.Version 'already loaded in session'
            }
            continue
        }

        $have = Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending | Select-Object -First 1
        if (-not $have -and -not $NoInstall.IsPresent) {
            try {
                if (-not $Quiet.IsPresent) { Write-Host ("Installing $mod (CurrentUser) ...") -ForegroundColor DarkCyan }
                Install-Module -Name $mod -MinimumVersion $needed -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                $have = Get-Module -ListAvailable -Name $mod | Sort-Object Version -Descending | Select-Object -First 1
            } catch {
                Add-Row $mod 'INSTALL-FAILED' $null $_.Exception.Message
                continue
            }
        }
        if (-not $have) { Add-Row $mod 'MISSING' $null 'not installed and -NoInstall'; continue }
        if ($have.Version -lt $needed) {
            Add-Row $mod 'TOO-OLD' $have.Version "needs >= $needed, have $($have.Version)"
            continue
        }
        try {
            Import-Module -Name $mod -MinimumVersion $needed -ErrorAction Stop
            Add-Row $mod 'LOADED' $have.Version 'imported'
        } catch {
            # Last-ditch: try without -MinimumVersion in case an older copy is
            # AppDomain-locked. If it sticks at any version, that's still useful.
            try {
                Import-Module -Name $mod -ErrorAction Stop
                $loadedVer = (Get-Module -Name $mod | Select-Object -First 1).Version
                Add-Row $mod 'LOADED-FALLBACK' $loadedVer "could not load $needed (AppDomain locked?); using $loadedVer instead"
            } catch {
                Add-Row $mod 'IMPORT-FAILED' $have.Version $_.Exception.Message
            }
        }
    }

    # Optional modules — never auto-install, but report presence
    foreach ($mod in $optionalModules) {
        $have = Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending | Select-Object -First 1
        if ($have) {
            try {
                Import-Module -Name $mod -Force -ErrorAction Stop
                Add-Row $mod 'LOADED-OPTIONAL' $have.Version 'imported (optional)'
            } catch {
                Add-Row $mod 'IMPORT-FAILED-OPTIONAL' $have.Version $_.Exception.Message
            }
        } else {
            Add-Row $mod 'NOT-INSTALLED-OPTIONAL' $null 'not installed (optional)'
        }
    }

    if (-not $Quiet.IsPresent) {
        $results | Format-Table -AutoSize | Out-String | Write-Host
    }
    # 1.0.2 — LOADED-OLDER + LOADED-FALLBACK count as success (the module is usable
    # in the session, just at a non-preferred version). Only true failures count.
    $failedRequired = @($results | Where-Object { $_.Status -in @('MISSING','TOO-OLD','INSTALL-FAILED','IMPORT-FAILED') })
    $ok = ($failedRequired.Count -eq 0)
    [pscustomobject]@{
        Ok                = $ok
        FailedRequired    = $failedRequired.Count
        Modules           = @($results)
        Platform          = (Get-KriticalPlatform)
        Timestamp         = (Get-Date).ToUniversalTime()
    }
}

function Get-KriticalFoundationStatus {
    <#
    .SYNOPSIS
        Read-only foundation status without installing/loading anything.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $names = @('PSFramework','PSSharedGoods','PSWriteHTML','ImportExcel','PSWriteOffice','PSWriteWord','PSWritePDF')
    $rows = foreach ($n in $names) {
        $have = Get-Module -ListAvailable -Name $n -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending | Select-Object -First 1
        [pscustomobject]@{
            Module    = $n
            Installed = [bool]$have
            Version   = if ($have) { $have.Version } else { $null }
            Loaded    = [bool](Get-Module -Name $n -ErrorAction SilentlyContinue)
        }
    }
    [pscustomobject]@{ Modules = @($rows); Platform = (Get-KriticalPlatform) }
}
