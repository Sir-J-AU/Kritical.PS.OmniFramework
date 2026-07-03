function Start-KriticalLogSession {
    <#
    .SYNOPSIS
        Starts a PSFramework log session under the Kritical namespace.
        Falls back to plain file logging if PSFramework isn't loaded.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Name = 'Krit',
        [string] $LogDir = (Join-Path $env:LOCALAPPDATA 'Kritical/Logs'),
        [string] $Provider = 'logfile'
    )
    New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue | Out-Null
    $usePsf = $false
    try {
        if (Get-Module -ListAvailable -Name PSFramework) {
            Import-Module PSFramework -Force -ErrorAction Stop
            $usePsf = $true
            $set = @{
                Name         = $Name
                FilePath     = (Join-Path $LogDir ("$Name-{0:yyyyMMdd}.log" -f (Get-Date)))
                FileType     = 'CMTrace'
                Enabled      = $true
            }
            Set-PSFLoggingProvider @set -Provider $Provider -ErrorAction Stop
        }
    } catch { $usePsf = $false }
    [pscustomobject]@{
        SessionName = $Name
        LogDir      = $LogDir
        Backend     = if ($usePsf) { 'PSFramework' } else { 'plain-file' }
        Started     = (Get-Date).ToUniversalTime()
    }
}

function Stop-KriticalLogSession {
    [CmdletBinding()]
    param([string] $Name = 'Krit')
    try { if (Get-Module PSFramework) { Set-PSFLoggingProvider -Name $Name -Enabled $false -ErrorAction SilentlyContinue } } catch { }
    Get-PSFMessage -ErrorAction SilentlyContinue | Out-Null
    Wait-PSFMessage -ErrorAction SilentlyContinue
}

function Write-KriticalLog {
    <#
    .SYNOPSIS
        Structured logger. Uses PSFramework's Write-PSFMessage when available,
        else writes to the host + a plain log file under %LOCALAPPDATA%\Kritical\Logs.

    .EXAMPLE
        Write-KriticalLog -Level Info -Message 'Hardening pass starting' -Tag 'krit-harden','phase-1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('Debug','Verbose','Info','Warning','Error','Critical')] [string] $Level = 'Info',
        [string[]] $Tag,
        [hashtable] $Data,
        [string] $LogDir = (Join-Path $env:LOCALAPPDATA 'Kritical/Logs')
    )
    $usePsf = Get-Module -Name PSFramework -ErrorAction SilentlyContinue
    if ($usePsf) {
        $psfLevel = switch ($Level) { 'Debug' {'Debug'} 'Verbose' {'Verbose'} 'Info' {'Host'} 'Warning' {'Warning'} 'Error' {'SomewhatVerbose'} 'Critical' {'Critical'} default {'Host'} }
        try {
            $params = @{ Message = $Message; Level = $psfLevel }
            if ($Tag)  { $params.Tag = $Tag }
            if ($Data) { $params.Data = $Data }
            Write-PSFMessage @params
            return
        } catch { }
    }
    # Plain fallback
    New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue | Out-Null
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $entry = [ordered]@{ ts=$ts; level=$Level; msg=$Message }
    if ($Tag)  { $entry.tag  = $Tag }
    if ($Data) { $entry.data = $Data }
    $line = ($entry | ConvertTo-Json -Compress)
    $file = Join-Path $LogDir ("krit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    $color = switch ($Level) { 'Error' {'Red'} 'Critical' {'Red'} 'Warning' {'Yellow'} 'Debug' {'DarkGray'} default {'Gray'} }
    Write-Host ("[$Level] $Message") -ForegroundColor $color
}
