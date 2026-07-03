$script:KriticalBrandSpecCache = $null   # strict-mode safe initialiser; module-scope cache.

function Get-KriticalBrandSpec {
    <#
    .SYNOPSIS
        Loads the canonical Kritical brand specification (brand-spec.json) with
        resolution-order fallbacks and per-session caching.

    .DESCRIPTION
        Single source of truth for every Kritical-branded artefact: colours,
        fonts, corporate identity, contact details, logo paths, template paths.

        Resolution order (first hit wins):
          1. Explicit -Path
          2. $env:KRIT_BRAND_SPEC_PATH
          3. $env:USERPROFILE\OneDrive - Kritical Pty Ltd\Kritical-Branding\public\brand-spec.json
          4. (cross-platform) /usr/share/kritical-branding/brand-spec.json
          5. Module-bundled Assets/brand-spec.json (last-ditch fallback for fresh installs)

        Cached at $script:KriticalBrandSpecCache; use -Refresh to force re-read.

    .PARAMETER Path
        Explicit override path.

    .PARAMETER Refresh
        Force re-load even if cached.

    .EXAMPLE
        $spec = Get-KriticalBrandSpec
        $primary = $spec.colours.primary.kriticalDarkBlue

    .EXAMPLE
        $spec = Get-KriticalBrandSpec -Refresh
        $spec.entity.abn

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
        Inventory: Github/KRTPax8ToShopifyConnector/reference/KRITICAL-BRAND-ASSET-INVENTORY-1507.md
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Path,
        [switch] $Refresh
    )

    if ($script:KriticalBrandSpecCache -and -not $Refresh.IsPresent -and -not $Path) {
        return $script:KriticalBrandSpecCache
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($Path) { $candidates.Add($Path) }
    $envPath = $env:KRIT_BRAND_SPEC_PATH
    if ($envPath) { $candidates.Add($envPath) }
    if ($env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Kritical-Branding\public\brand-spec.json'))
    }
    if ($env:HOME) {
        $candidates.Add((Join-Path $env:HOME 'OneDrive - Kritical Pty Ltd/Kritical-Branding/public/brand-spec.json'))
        $candidates.Add('/usr/share/kritical-branding/brand-spec.json')
    }
    $moduleAsset = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'Assets/brand-spec.json'
    $candidates.Add($moduleAsset)

    $found = $null
    foreach ($p in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) { $found = $p; break }
    }

    if (-not $found) {
        # Minimal hard-coded fallback so the module never throws if the file is missing.
        $spec = [pscustomobject]@{
            _meta      = [pscustomobject]@{ source = 'fallback'; note = 'No brand-spec.json found; using minimal hard-coded values' }
            entity     = [pscustomobject]@{
                legalName         = 'Kritical Pty Ltd'
                tradeName         = 'Kritical'
                trademark         = 'Kritical(TM)'
                abn               = '39 687 048 086'
                acn               = '687 048 086'
                registeredAddress = 'Level 4, 60 Moorabool Street, Geelong VIC 3220, Australia'
                governingLaw      = 'Victoria, Australia'
            }
            contact    = [pscustomobject]@{
                phoneMain    = '1300 274 655'
                emailSales   = 'sales@kritical.net'
                webPrimary   = 'https://kritical.net/'
            }
            messaging  = [pscustomobject]@{
                tagline       = 'Your last call. And your first move.'
                positioning   = "Geelong & The Bellarine's IT & Cybersecurity Specialists"
                directorName  = 'Joshua Finley'
                directorTitle = 'Director'
            }
            colours    = [pscustomobject]@{
                primary   = [pscustomobject]@{ kriticalDarkBlue = '#13365C' }
                secondary = [pscustomobject]@{ kriticalCyan = '#15AFD1'; lightGrey = '#D9D9D9' }
                tertiary  = [pscustomobject]@{ white = '#FFFFFF'; mediumGrey = '#6D6E71'; black = '#000000' }
            }
            typography = [pscustomobject]@{
                headings     = [pscustomobject]@{ family = 'Roboto'; weight = 'Regular'; size_pt = 42 }
                subheadings  = [pscustomobject]@{ family = 'Assistant'; weight = 'Medium'; size_pt = 21 }
            }
        }
        $script:KriticalBrandSpecCache = $spec
        Write-Verbose 'Get-KriticalBrandSpec: no spec file found; returning hard-coded fallback.'
        return $spec
    }

    try {
        $raw = Get-Content -LiteralPath $found -Raw -ErrorAction Stop
        $spec = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse brand-spec.json at ${found}: $($_.Exception.Message)"
    }

    # Attach the resolved source path for diagnostics.
    try { $spec | Add-Member -NotePropertyName _sourcePath -NotePropertyValue $found -Force } catch { }

    $script:KriticalBrandSpecCache = $spec
    Write-Verbose ("Get-KriticalBrandSpec: loaded from {0}" -f $found)
    return $spec
}
