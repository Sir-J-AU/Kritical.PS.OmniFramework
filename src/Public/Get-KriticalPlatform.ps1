function Test-KriticalIsAdmin {
    <#
    .SYNOPSIS
        True on Windows when the process token has Administrator role; on
        macOS/Linux when EUID = 0.
    #>
    [CmdletBinding()] [OutputType([bool])] param()
    if ($IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        try {
            $cur = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            return $cur.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
        } catch { return $false }
    }
    try { return ([int](id -u 2>$null) -eq 0) } catch { return $false }
}

function Test-KriticalIsElevated {
    <#
    .SYNOPSIS
        Synonym for Test-KriticalIsAdmin (some scripts read more naturally with this name).
    #>
    [CmdletBinding()] [OutputType([bool])] param()
    return (Test-KriticalIsAdmin)
}

function Get-KriticalPlatform {
    <#
    .SYNOPSIS
        Returns a normalised platform descriptor across Windows / macOS / Linux.

    .DESCRIPTION
        Probes the actual OS via .NET RuntimeInformation + /etc/os-release +
        sw_vers + Get-CimInstance. Returns a single PSCustomObject regardless
        of host, so downstream callers branch on object properties rather than
        on $IsWindows / $IsLinux / $IsMacOS scattered throughout.

    .OUTPUTS
        PSCustomObject {
            Family            (Windows | macOS | Linux | Unknown)
            DistroId          (windows | macos | ubuntu | debian | rhel | fedora | arch | alpine | suse | ...)
            DistroName        (humanised)
            Version           (Version)
            VersionString     (raw)
            Build             (Windows build number / kernel release on *nix)
            Architecture      (X64 | Arm64 | X86 | Arm)
            HostName          (computer name)
            UserName          (current user)
            IsAdmin           (bool)
            PSEdition         (Desktop | Core)
            PSVersion         (Version)
            RawProbe          (the source dict used to derive the above — for diagnostics)
        }

    .EXAMPLE
        Get-KriticalPlatform | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $family = 'Unknown'
    $distroId = 'unknown'
    $distroName = 'unknown'
    $version = $null
    $versionString = ''
    $build = ''
    $raw = @{}

    # Detect family
    $rti = [System.Runtime.InteropServices.RuntimeInformation]
    $os = [System.Runtime.InteropServices.OSPlatform]
    if ($rti::IsOSPlatform($os::Windows)) { $family = 'Windows' }
    elseif ($rti::IsOSPlatform($os::OSX))  { $family = 'macOS' }
    elseif ($rti::IsOSPlatform($os::Linux)) { $family = 'Linux' }

    switch ($family) {
        'Windows' {
            $distroId   = 'windows'
            $distroName = 'Microsoft Windows'
            try {
                $cim = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $raw.cim = @{ Caption=$cim.Caption; Version=$cim.Version; BuildNumber=$cim.BuildNumber; OSArchitecture=$cim.OSArchitecture }
                $versionString = $cim.Version
                if ($cim.Version) { try { $version = [Version]$cim.Version } catch { } }
                $build = $cim.BuildNumber
                if ($cim.Caption -match 'Windows\s+(11|10|Server\s+\d+)') { $distroName = $cim.Caption.Trim() }
            } catch {
                $versionString = (Get-Item -LiteralPath 'C:\Windows\System32\ntoskrnl.exe' -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
            }
        }
        'macOS' {
            $distroId   = 'macos'
            $distroName = 'macOS'
            try {
                $sw = (& sw_vers 2>$null) -join "`n"
                $raw.swvers = $sw
                if ($sw -match 'ProductName:\s*(.+)') { $distroName = $matches[1].Trim() }
                if ($sw -match 'ProductVersion:\s*([\d\.]+)') { $versionString = $matches[1]; try { $version = [Version]$versionString } catch { } }
                if ($sw -match 'BuildVersion:\s*(.+)') { $build = $matches[1].Trim() }
            } catch { }
        }
        'Linux' {
            $osRelease = '/etc/os-release'
            $raw.osrelease = if (Test-Path -LiteralPath $osRelease) { Get-Content -LiteralPath $osRelease -Raw } else { '' }
            if ($raw.osrelease) {
                if ($raw.osrelease -match '(?m)^ID=("?)([^"\r\n]+)\1') { $distroId   = $matches[2].Trim() }
                if ($raw.osrelease -match '(?m)^NAME=("?)([^"\r\n]+)\1') { $distroName = $matches[2].Trim() }
                if ($raw.osrelease -match '(?m)^VERSION_ID=("?)([^"\r\n]+)\1') {
                    $versionString = $matches[2].Trim()
                    try { $version = [Version]$versionString } catch { }
                }
            } elseif (Test-Path -LiteralPath '/etc/lsb-release') {
                $raw.lsbrelease = Get-Content -LiteralPath '/etc/lsb-release' -Raw
                if ($raw.lsbrelease -match 'DISTRIB_ID=(.+)')      { $distroId = $matches[1].Trim().ToLowerInvariant() }
                if ($raw.lsbrelease -match 'DISTRIB_RELEASE=(.+)') { $versionString = $matches[1].Trim() }
                if ($raw.lsbrelease -match 'DISTRIB_DESCRIPTION="?([^"]+)"?') { $distroName = $matches[1].Trim() }
            }
            try { $build = (uname -r 2>$null).Trim() } catch { }
        }
    }

    # Architecture
    $arch = 'Unknown'
    try {
        $arch = switch ($rti::OSArchitecture) {
            'X64'   { 'X64' }
            'Arm64' { 'Arm64' }
            'X86'   { 'X86' }
            'Arm'   { 'Arm' }
            default { $rti::OSArchitecture.ToString() }
        }
    } catch { }

    [pscustomobject]@{
        Family        = $family
        DistroId      = $distroId
        DistroName    = $distroName
        Version       = $version
        VersionString = $versionString
        Build         = $build
        Architecture  = $arch
        HostName      = [System.Net.Dns]::GetHostName()
        UserName      = [System.Environment]::UserName
        IsAdmin       = (Test-KriticalIsAdmin)
        PSEdition     = $PSVersionTable.PSEdition
        PSVersion     = $PSVersionTable.PSVersion
        RawProbe      = $raw
    }
}
