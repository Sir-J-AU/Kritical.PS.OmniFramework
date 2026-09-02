function Resolve-KriticalRepoRoot {
    <#
    .SYNOPSIS
        Walks up from the current directory until it finds a Kritical repo
        marker (.git, krit-project.json, or pax8-framework.settings.json).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $StartPath = (Get-Location).Path)
    $dir = $StartPath
    # Repo-root markers — kept brand-neutral (no AI-agent file names).
    $markers = @('.git','krit-project.json','config/krit-project.json','config/pax8-framework.settings.json','pax8-framework.settings.json','Kritical.PS.OmniFramework.psd1')
    for ($i=0; $i -lt 12 -and $dir; $i++) {
        foreach ($m in $markers) {
            if (Test-Path -LiteralPath (Join-Path $dir $m)) { return $dir }
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-KriticalConfig {
    <#
    .SYNOPSIS
        Loads a JSON config file from the resolved repo root. Default name:
        krit-project.json (preferred) or config/pax8-framework.settings.json (legacy).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $StartPath = (Get-Location).Path,
        [string] $ConfigName
    )
    $root = Resolve-KriticalRepoRoot -StartPath $StartPath
    if (-not $root) { throw "Could not resolve a Kritical repo root above $StartPath" }
    $candidates = if ($ConfigName) { @($ConfigName) } else {
        @('krit-project.json','config/krit-project.json','config/pax8-framework.settings.json','pax8-framework.settings.json')
    }
    foreach ($c in $candidates) {
        $full = Join-Path $root $c
        if (Test-Path -LiteralPath $full) {
            # .5231 (lens-hunt): ConvertFrom-Json throws a terminating error on malformed
            # JSON, crashing every dependent caller. Guard it and surface a clear warning
            # while returning a null Config (fallback) instead of taking the process down.
            $parsed = $null
            try {
                $parsed = (Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                Write-Warning "Config at '$full' is not valid JSON: $($_.Exception.Message)"
            }
            return [pscustomobject]@{
                RepoRoot   = $root
                ConfigPath = $full
                ConfigName = $c
                Config     = $parsed
            }
        }
    }
    return [pscustomobject]@{ RepoRoot = $root; ConfigPath = $null; ConfigName = $null; Config = $null }
}

function Get-KriticalProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $StartPath = (Get-Location).Path, [Parameter(Mandatory)] [string] $Name)
    $cfg = Get-KriticalConfig -StartPath $StartPath
    if (-not $cfg.Config) { return $null }
    $projects = $cfg.Config.projects
    if (-not $projects) { return $null }
    $p = $projects.PSObject.Properties | Where-Object Name -eq $Name | Select-Object -First 1
    if (-not $p) { return $null }
    return $p.Value
}

function Get-KriticalPath {
    <#
    .SYNOPSIS
        Resolves a named path under the Kritical config 'paths' section.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $StartPath = (Get-Location).Path, [Parameter(Mandatory)] [string] $Name)
    $cfg = Get-KriticalConfig -StartPath $StartPath
    if (-not $cfg.Config) { return $null }
    $paths = $cfg.Config.paths
    if (-not $paths) { return $null }
    $p = $paths.PSObject.Properties | Where-Object Name -eq $Name | Select-Object -First 1
    if (-not $p) { return $null }
    $val = [string]$p.Value
    if ([System.IO.Path]::IsPathRooted($val)) { return $val }
    return (Join-Path $cfg.RepoRoot $val)
}

function Test-KriticalSecretsLoaded {
    <#
    .SYNOPSIS
        Reports whether the canonical Kritical secrets folder is reachable AND
        a given list of expected secret files are present. Read-only.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]   $SecretsDir = (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos'),
        [string[]] $RequireFiles
    )
    $folderOk = Test-Path -LiteralPath $SecretsDir
    $missing = @()
    if ($folderOk -and $RequireFiles) {
        foreach ($f in $RequireFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $SecretsDir $f))) { $missing += $f }
        }
    }
    [pscustomobject]@{
        SecretsDir       = $SecretsDir
        FolderPresent    = $folderOk
        RequiredFiles    = @($RequireFiles)
        MissingFiles     = @($missing)
        Ok               = ($folderOk -and ($missing.Count -eq 0))
    }
}
