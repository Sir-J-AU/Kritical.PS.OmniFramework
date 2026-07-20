function Get-KriticalBannerCanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $candidates = @(
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Kritical-Branding\public\KriticalLogo.txt'),
        (Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\KriticalLogo.txt'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'Assets/kritical-logo.txt')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

function Get-KriticalBanner {
    <#
    .SYNOPSIS
        Returns the canonical Kritical banner string (SirJ's Deaddrop / A Seriously Kritical(TM) Production).
    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Title, [switch] $Compact, [string] $LogoPath)
    if ($Compact) {
        $line = '[Kritical(TM)] A Seriously Kritical Production | +61 1300 274 655 | sales at kritical dot net'
        if ($Title) { $line += " - $Title" }
        return $line
    }
    if (-not $LogoPath) { $LogoPath = Get-KriticalBannerCanonicalPath }
    if (-not $LogoPath -or -not (Test-Path -LiteralPath $LogoPath)) {
        $line = '[Kritical(TM)] A Seriously Kritical Production | +61 1300 274 655 | sales at kritical dot net'
        if ($Title) { $line += "`n--- $Title ---" }
        return $line
    }
    $logo = Get-Content -LiteralPath $LogoPath -Raw
    if ($Title) { return ($logo.TrimEnd() + "`n`n--- $Title ---`n") }
    return $logo
}

function Test-KriticalAgenticSession {
    <#
    .SYNOPSIS
        True when running inside an AI coding agent (Claude Code, etc.) rather than
        an interactive human terminal -- the banner's ASCII art + sales pitch has zero
        value to an agent and costs real tokens on every invocation.
    .NOTES
        Auto-detects via env vars agent harnesses already set (no convention needed):
        $env:CLAUDECODE (Claude Code CLI/SDK), $env:AI_AGENT (generic marker this
        estate's own tooling also honors). $env:KRIT_NO_BANNER is an explicit manual
        opt-out for any other caller (CI, other agents, a human who just wants quiet).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]($env:KRIT_NO_BANNER -or $env:CLAUDECODE -or $env:AI_AGENT -or $env:CURSOR_TRACE_ID -or $env:COPILOT_AGENT)
}

function Write-KriticalBanner {
    [CmdletBinding()]
    param([string] $Title, [switch] $Compact, [switch] $NoColor, [string] $LogoPath, [switch] $Force)
    if ((Test-KriticalAgenticSession) -and -not $Force.IsPresent) { return }
    $useColor = -not $NoColor.IsPresent -and $null -ne $Host.UI.RawUI -and $null -ne $Host.UI.RawUI.ForegroundColor
    $banner = Get-KriticalBanner -Title $Title -Compact:$Compact -LogoPath $LogoPath
    if (-not $useColor) { Write-Output $banner; return }
    foreach ($l in ($banner -split "`r?`n")) {
        $color = 'DarkCyan'
        if ($l -match 'Kritical|SirJ|first move|last call|Seriously Kritical|---\s|★|☆') { $color = 'Yellow' }
        elseif ($l -match '274 655|kritical dot net') { $color = 'DarkCyan' }
        Write-Host $l -ForegroundColor $color
    }
}
