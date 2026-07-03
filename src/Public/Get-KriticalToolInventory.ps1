function Get-KriticalToolInventoryDefaultPaths {
    <#
    .SYNOPSIS
        Returns the canonical per-OS list of standard tool-search paths
        (LSB + FHS for Linux, Apple-recommended for macOS, Windows app-install
        conventions for Windows). Used by Get-KriticalToolInventory.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string] $Family)
    switch ($Family) {
        'Windows' {
            $paths = @(
                "$env:WINDIR\System32",
                "$env:WINDIR",
                "$env:ProgramFiles",
                ${env:ProgramFiles(x86)},
                "$env:LOCALAPPDATA\Microsoft\WindowsApps",
                "$env:LOCALAPPDATA\Programs",
                "$env:USERPROFILE\.dotnet\tools",
                'C:\ProgramData\chocolatey\bin',
                "$env:USERPROFILE\scoop\shims",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
            )
        }
        'macOS' {
            $paths = @('/usr/local/bin','/opt/homebrew/bin','/opt/local/bin','/usr/bin','/bin','/usr/sbin','/sbin','/Library/Apple/usr/bin')
            $extra = "$HOME/.local/bin"
            if (Test-Path -LiteralPath $extra) { $paths += $extra }
        }
        'Linux' {
            # FHS / LSB standard paths first, then snap / flatpak / language tool dirs
            $paths = @('/usr/local/sbin','/usr/local/bin','/usr/sbin','/usr/bin','/sbin','/bin','/opt','/snap/bin','/var/lib/flatpak/exports/bin')
            $extra = "$HOME/.local/bin"
            if (Test-Path -LiteralPath $extra) { $paths += $extra }
        }
        default { $paths = @() }
    }
    # De-dup + filter to existing paths
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = @()
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($seen.Add($p) -and (Test-Path -LiteralPath $p)) { $out += $p }
    }
    return $out
}

function Find-KriticalTool {
    <#
    .SYNOPSIS
        Finds a tool by name across the OS-standard search paths.
    .DESCRIPTION
        Returns every matching executable file (so you can spot duplicates
        across PATH entries). Honours Windows .exe/.cmd/.bat/.ps1 extension list.
    .EXAMPLE
        Find-KriticalTool -Name git
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string[]] $ExtraPath
    )
    $plat = Get-KriticalPlatform
    $paths = Get-KriticalToolInventoryDefaultPaths -Family $plat.Family
    if ($ExtraPath) { $paths += $ExtraPath | Where-Object { Test-Path -LiteralPath $_ } }
    $candExts = if ($plat.Family -eq 'Windows') { @('','.exe','.cmd','.bat','.ps1','.com') } else { @('') }
    $hits = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($p in $paths) {
        foreach ($e in $candExts) {
            $full = Join-Path $p ($Name + $e)
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                $fi = Get-Item -LiteralPath $full
                $hits.Add([pscustomobject]@{
                    Name         = $Name
                    Path         = $full
                    Directory    = $p
                    Extension    = $e
                    Size         = $fi.Length
                    LastModified = $fi.LastWriteTime
                    IsExecutable = $true
                })
            }
        }
    }
    $hits
}

function Test-KriticalToolPresent {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Name, [string[]] $ExtraPath)
    @(Find-KriticalTool -Name $Name -ExtraPath $ExtraPath).Count -gt 0
}

function Get-KriticalToolInventory {
    <#
    .SYNOPSIS
        FHS/LSB-aware multi-OS tool inventory. Reports presence + first-found path
        + duplicate locations for a configurable tool list, OR for the full
        Kritical-canonical list when none is supplied.

    .DESCRIPTION
        On first run with no -Tool list, scans for the Kritical canonical
        tool set: shells, package managers, archive tools, programming
        runtimes, security tools, container/cloud CLIs, SSH/git, etc.

    .EXAMPLE
        Get-KriticalToolInventory | Where-Object { $_.Present } | Format-Table Name, FirstPath
    .EXAMPLE
        Get-KriticalToolInventory -Tool git, kubectl, terraform -IncludeDuplicates
    .EXAMPLE
        # JSON for piping into a dashboard
        Get-KriticalToolInventory | ConvertTo-Json -Depth 5

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string[]] $Tool,
        [string[]] $ExtraPath,
        [switch] $IncludeDuplicates
    )
    if (-not $Tool -or $Tool.Count -eq 0) {
        $Tool = @(
            # Shells / interpreters
            'pwsh','powershell','bash','zsh','sh','fish','nu',
            # Source control
            'git','gh','svn','hg',
            # Build / package
            'make','cmake','ninja','dotnet','msbuild','gcc','clang',
            # Runtimes
            'node','npm','pnpm','yarn','deno','bun','python','python3','py','pip','pip3','ruby','gem','perl','php','go','rustc','cargo','java','mvn','gradle',
            # Containers / cloud
            'docker','podman','buildah','kubectl','helm','minikube','k3d','terraform','tofu','ansible','az','aws','gcloud','oc','crictl',
            # SSH / net
            'ssh','sshd','scp','curl','wget','rsync','nc','nmap','traceroute','dig','nslookup','ping','tcpdump','iperf3',
            # Editors
            'code','code-insiders','vim','nvim','emacs','nano','micro',
            # Archive / encryption
            '7z','tar','zip','unzip','gpg','openssl','age',
            # Security / hardening
            'hardeningkitty','lgpo','sigcheck','sigcheck64','autoruns','procmon','procexp','accesschk',
            # JSON/YAML/data
            'jq','yq','xmlstarlet','xq',
            # System
            'systemctl','journalctl','service','sc','wmic','reg','wevtutil','auditpol','secedit','dism','sfc',
            # File systems
            'lsblk','blkid','df','du','ls','dir',
            # Package mgrs
            'apt','apt-get','dnf','yum','zypper','pacman','apk','brew','port','winget','choco','scoop'
        )
    }
    $plat = Get-KriticalPlatform
    $paths = Get-KriticalToolInventoryDefaultPaths -Family $plat.Family
    if ($ExtraPath) { $paths += $ExtraPath | Where-Object { Test-Path -LiteralPath $_ } }

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($t in $Tool) {
        $hits = @(Find-KriticalTool -Name $t -ExtraPath $ExtraPath)
        $row = [pscustomobject]@{
            Name       = $t
            Present    = ($hits.Count -gt 0)
            FirstPath  = if ($hits.Count -gt 0) { $hits[0].Path } else { $null }
            HitCount   = $hits.Count
            AllPaths   = if ($IncludeDuplicates) { @($hits | ForEach-Object { $_.Path }) } else { $null }
        }
        $rows.Add($row)
    }
    return @($rows)
}
