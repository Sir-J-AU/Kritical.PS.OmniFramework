function New-KriticalBrandedDocument {
    <#
    .SYNOPSIS
        Renders a Markdown (or HTML) source file to a Kritical-branded artefact
        in one or more output formats: PDF, DOCX, HTML.

    .DESCRIPTION
        End-to-end pipeline for customer proposals, internal reports, training
        decks etc. Pulls brand spec from Get-KriticalBrandSpec (single source of
        truth). Applies:
          - Primary colour (#13365C Kritical dark blue) on headings + tables
          - Secondary colour (#15AFD1 Kritical cyan) on accents
          - Roboto headings + Assistant sub-headings (via @font-face when fonts
            available in Kritical-Branding/public/fonts/)
          - Horizontal_Logo.png in header
          - Canonical footer (ABN, ACN, address, tagline, phone, email, web)
          - Optional Outlook email signature appended

        Render engines (auto-detected; first match wins):
          - PDF:  Pandoc + wkhtmltopdf  (preferred)
                  Pandoc + Chrome / Edge headless  (fallback)
                  Markdown-it + Chrome headless  (last-ditch)
          - DOCX: Pandoc --reference-doc=Kritical-BaseTemplate-CURRENT.docx
          - HTML: Pandoc + brand-aligned CSS, single-file with base64 images

        Output filename: <CustomerName>-<DocumentTitle>-<utc-stamp>.<ext>

    .PARAMETER Source
        Path to source .md or .html file.

    .PARAMETER OutDir
        Output directory. Created if missing.

    .PARAMETER Format
        One or more of: PDF, DOCX, HTML. Default: PDF + DOCX + HTML.

    .PARAMETER CustomerName
        Customer name (e.g. 'Kitchenworx', 'EES'). Used in output filename + Word
        --metadata for use in templates.

    .PARAMETER DocumentTitle
        Short document title (e.g. 'Proposal-Cover', 'Rate-Card').

    .PARAMETER EmbedSignature
        Append the Outlook signature (email-signature.htm) at the end of the
        rendered HTML / PDF (not DOCX).

    .PARAMETER NoFooter
        Skip the canonical footer (rare; only for unbranded internal previews).

    .PARAMETER NoBanner
        Skip the Kritical banner Write-Host on console.

    .EXAMPLE
        New-KriticalBrandedDocument -Source .\Kitchenworx-Proposal.md `
            -OutDir .\out -CustomerName Kitchenworx -DocumentTitle Proposal-Cover

    .EXAMPLE
        # PDF only
        New-KriticalBrandedDocument -Source .\report.md -OutDir .\out -Format PDF `
            -CustomerName Internal -DocumentTitle Q2-Report

    .EXAMPLE
        # Bulk a folder of .md files
        Get-ChildItem .\drafts\*.md | ForEach-Object {
            New-KriticalBrandedDocument -Source $_.FullName -OutDir .\out `
                -CustomerName EES -DocumentTitle ($_.BaseName)
        }

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
        Inventory: Github/KRTPax8ToShopifyConnector/reference/KRITICAL-BRAND-ASSET-INVENTORY-1507.md
        Architecture: KRITICAL-BRAND-ASSET-INVENTORY-1507 section 8
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [Parameter(Mandatory)] [string]   $OutDir,
        [ValidateSet('PDF','DOCX','HTML')] [string[]] $Format = @('PDF','DOCX','HTML'),
        [Parameter(Mandatory)] [string]   $CustomerName,
        [Parameter(Mandatory)] [string]   $DocumentTitle,
        [switch] $EmbedSignature,
        [switch] $NoFooter,
        [switch] $NoBanner
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source file not found: $Source"
    }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    if (-not $NoBanner.IsPresent) {
        try { Write-KriticalBanner -Title "BrandedDocument: $CustomerName - $DocumentTitle" -Compact } catch { }
    }

    $spec = Get-KriticalBrandSpec
    $brandRoot = $null
    if ($env:USERPROFILE) {
        $candidate = Join-Path $env:USERPROFILE 'OneDrive - Kritical Pty Ltd\Kritical-Branding\public'
        if (Test-Path -LiteralPath $candidate) { $brandRoot = $candidate }
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
    $safeCustomer = ($CustomerName -replace '[^\w\-]','_')
    $safeTitle    = ($DocumentTitle -replace '[^\w\-]','_')
    $baseName     = "{0}-{1}-{2}" -f $safeCustomer, $safeTitle, $stamp

    # Build the brand-aligned CSS once; reused for HTML + PDF-via-headless paths.
    $primary    = $spec.colours.primary.kriticalDarkBlue
    $secondary  = $spec.colours.secondary.kriticalCyan
    $lightGrey  = $spec.colours.secondary.lightGrey
    $textColor  = $spec.colours.tertiary.black
    $entity     = $spec.entity
    $contact    = $spec.contact
    $messaging  = $spec.messaging

    # 1.1.2 — load logo + JoshCreations branded banner + footer images as data-URIs
    $detectImageMime = {
        param([byte[]] $bytes, [string] $path)

        if ($bytes.Length -ge 12) {
            if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47 -and $bytes[4] -eq 0x0D -and $bytes[5] -eq 0x0A -and $bytes[6] -eq 0x1A -and $bytes[7] -eq 0x0A) { return 'image/png' }
            if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return 'image/jpeg' }
            $riff = [Text.Encoding]::ASCII.GetString($bytes, 0, 4)
            $webp = [Text.Encoding]::ASCII.GetString($bytes, 8, 4)
            if ($riff -eq 'RIFF' -and $webp -eq 'WEBP') { return 'image/webp' }
        }
        if ($bytes.Length -ge 6) {
            $prefix = [Text.Encoding]::ASCII.GetString($bytes, 0, 6)
            if ($prefix -eq 'GIF87a' -or $prefix -eq 'GIF89a') { return 'image/gif' }
        }

        switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
            '.svg'  { 'image/svg+xml' }
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
            '.webp' { 'image/webp' }
            '.gif'  { 'image/gif' }
            default { 'application/octet-stream' }
        }
    }

    $imgToDataUri = {
        param([string] $path, [string] $mime)
        if (Test-Path -LiteralPath $path) {
            $bytes = [IO.File]::ReadAllBytes($path)
            $mime = & $detectImageMime $bytes $path
            return ("data:{0};base64,{1}" -f $mime, [Convert]::ToBase64String($bytes))
        }
        return ''
    }

    $logoDataUri    = ''
    $partnerBadgeUris = @{}  # v1.1.5 — partner badges + logo all sourced from kritical.au harvest only
    if ($brandRoot) {
        # v1.1.5 — JoshCreations imagery removed end-to-end per operator directive 2026-06-25.
        # Cover uses kritical.au Horizontal_Logo (which already bakes in the tagline).
        # Footer uses kritical.au partner badges on navy band only.
        $logoCandidate   = Join-Path $brandRoot 'banners\from-kritical-au-20260625\Horizontal_Logo.png'
        $logoFallback    = Join-Path $brandRoot 'logos\Horizontal_Logo.png'
        $logoFallback2   = Join-Path $brandRoot 'logos\Original_Logo.png'
        $partnerSrc      = Join-Path $brandRoot 'banners\from-kritical-au-20260625'
        foreach ($cand in @($logoCandidate,$logoFallback,$logoFallback2)) {
            if (Test-Path -LiteralPath $cand) { $logoDataUri = & $imgToDataUri $cand 'image/png'; break }
        }
        if (Test-Path -LiteralPath $partnerSrc) {
            foreach ($pBadge in @('Microsoft_White.png','Pax8.png','Apple_2.png','Veeam.png','Lenovo.png','Crowdstrike-1-384x230.webp')) {
                $pPath = Join-Path $partnerSrc $pBadge
                if (Test-Path -LiteralPath $pPath) {
                    $partnerBadgeUris[$pBadge] = & $imgToDataUri $pPath 'image/png'
                }
            }
        }
    }

    $sigDataHtml = ''
    if ($EmbedSignature.IsPresent -and $brandRoot) {
        $sigPath = Join-Path $brandRoot 'email-signature.htm'
        if (Test-Path -LiteralPath $sigPath) {
            $sigDataHtml = Get-Content -LiteralPath $sigPath -Raw -Encoding UTF8
        }
    }

    # v1.1.4 — Single clean footer band: partner badges on navy + one row of contact + tagline. No duplicate image.
    $footerHtml = if ($NoFooter.IsPresent) { '' } else {
        @"
<footer class="kr-footer">
  __PARTNER_BADGE_ROW__
  <div class="kr-footer-line">
    <span class="kr-tagline"><em>$($messaging.tagline)</em></span>
  </div>
  <div class="kr-footer-line kr-corp">
    $($entity.legalName) &middot; ABN $($entity.abn) &middot; ACN $($entity.acn) &middot; $($entity.registeredAddress)
  </div>
  <div class="kr-footer-line kr-contact">
    $($contact.phoneMain) &middot; <a href="mailto:$($contact.emailSales)">$($contact.emailSales)</a> &middot; <a href="$($contact.webPrimary)">$($contact.webPrimary)</a>
  </div>
</footer>
"@
    }

    # v1.1.5 — Clean cover: kritical.au Horizontal_Logo (tagline baked in) + positioning text + clean contact line.
    $coverContactHtml = "<div class='kr-cover-contact'>$($contact.phoneMain) &middot; <a href='mailto:$($contact.emailSales)'>$($contact.emailSales)</a> &middot; <a href='$($contact.webPrimary)'>$($contact.webPrimary)</a></div>"
    $headerHtml = if ($logoDataUri) {
        @"
<div class="kr-cover">
  <img src="$logoDataUri" alt="Kritical" class="kr-cover-logo"/>
  <div class="kr-cover-positioning">$($messaging.positioning)</div>
  $coverContactHtml
</div>
"@
    } else {
        @"
<div class="kr-cover">
  <div class="kr-cover-wordmark">Kritical&trade;</div>
  <div class="kr-cover-tagline">$($messaging.tagline)</div>
  <div class="kr-cover-positioning">$($messaging.positioning)</div>
  $coverContactHtml
</div>
"@
    }

    # 1.1.3 — Partner badges row appended below the footer banner
    $partnerBadgeRowHtml = ''
    if ($partnerBadgeUris.Count -gt 0) {
        $badgesHtml = ($partnerBadgeUris.GetEnumerator() | Sort-Object Name | ForEach-Object {
            "<img src='$($_.Value)' alt='$([IO.Path]::GetFileNameWithoutExtension($_.Key))' class='kr-partner-badge'/>"
        }) -join "`n  "
        $partnerBadgeRowHtml = @"
<div class="kr-partner-row">
  <div class="kr-partner-label">Authorised partner of</div>
  <div class="kr-partner-badges">
  $badgesHtml
  </div>
</div>
"@
    }
    # Substitute partner-row placeholder into footer (after both defined)
    $footerHtml = $footerHtml.Replace('__PARTNER_BADGE_ROW__', $partnerBadgeRowHtml)

    $css = @"
@font-face { font-family:'Roboto';    src: local('Roboto'); font-weight: normal; }
@font-face { font-family:'Assistant'; src: local('Assistant'); font-weight: 500; }
* { box-sizing: border-box; }
html,body { margin:0; padding:0; }
/* v1.1.9.2 — kill browser default body top-spacing for HTML standalone view; @page handles PDF print */
body { font-family: 'Assistant', 'Segoe UI', Calibri, Arial, sans-serif; color:$textColor; line-height:1.65; font-size: 11pt; max-width: 920px; margin: 0 auto; padding: 0.6em 1.2em 3em 1.2em; background:#fff; }
@media screen { body { padding-top: 1.2em; } }
h1,h2,h3,h4 { font-family: 'Roboto', 'Segoe UI', Calibri, Arial, sans-serif; color:$primary; font-weight: 500; line-height:1.25; margin: 1.4em 0 0.6em 0; }
h1 { font-size: 26pt; border-bottom: 4px solid $primary; padding-bottom: 0.25em; margin: 0.2em 0 0.6em 0; }
.kr-cover + h1, .kr-cover + h2 { margin-top: 0; }
h2 { font-size: 16pt; border-bottom: 2px solid $secondary; padding-bottom: 0.2em; margin-top: 2em; }
h3 { font-size: 13pt; color: $primary; margin-top: 1.5em; }
h4 { font-size: 11.5pt; color: $secondary; }
p { margin: 0.6em 0; }
strong { color: $primary; font-weight: 600; }
a { color: $secondary; text-decoration: underline; text-decoration-color: $lightGrey; text-underline-offset: 2px; }
a:hover { text-decoration-color: $secondary; }
.doc-meta {
  margin: 0.4em 0 1.2em 0;
  padding: 0.75em 1em;
  border-left: 4px solid $secondary;
  background: #f7f9fb;
  font-size: 10pt;
  line-height: 1.35;
  page-break-inside: avoid;
  break-inside: avoid;
}
.doc-meta div { margin: 0.16em 0; }
.doc-meta strong {
  display: inline-block;
  min-width: 6.8em;
  color: $primary;
}
table { border-collapse: collapse; margin: 1em 0; width: 100%; font-size: 10pt; }
th, td { border: 1px solid $lightGrey; padding: 0.55em 0.8em; text-align: left; vertical-align: top; }
th { background: $primary; color: #fff; font-family: 'Roboto', Calibri, sans-serif; font-weight: 500; }
tr:nth-child(even) td { background: #f7f9fb; }
table.kr-gantt {
  border-collapse: separate;
  border-spacing: 0;
  table-layout: fixed;
  width: 100%;
  margin: 1em 0 1.4em 0;
  font-size: 8.5pt;
  page-break-inside: avoid;
  break-inside: avoid;
}
table.kr-gantt th,
table.kr-gantt td {
  border: 1px solid #cfd8e3;
  padding: 0.42em 0.45em;
  text-align: center;
  vertical-align: middle;
  line-height: 1.25;
}
table.kr-gantt thead th {
  background: $primary;
  color: #fff;
  font-weight: 600;
}
table.kr-gantt th:first-child,
table.kr-gantt td:first-child {
  width: 20%;
  text-align: left;
  background: #eef3f7;
  color: $primary;
  font-weight: 600;
}
table.kr-gantt tr:nth-child(even) td { background: #fff; }
table.kr-gantt .g-empty { background: #fff !important; color: transparent; }
table.kr-gantt .g-bar {
  color: #fff;
  font-family: 'Roboto', Calibri, sans-serif;
  font-weight: 600;
  text-align: center;
  letter-spacing: 0;
}
table.kr-gantt .g-navy { background: #13365C !important; }
table.kr-gantt .g-cyan { background: #0B83A5 !important; }
table.kr-gantt .g-green { background: #27754F !important; }
table.kr-gantt .g-amber { background: #A76209 !important; }
table.kr-gantt .g-plum { background: #6E3A78 !important; }
table.kr-gantt .g-slate { background: #4F6072 !important; }
table.kr-gantt .g-red { background: #A23B32 !important; }
.kr-gantt-note {
  margin: -0.4em 0 1.2em 0;
  font-size: 9pt;
  color: #4d5965;
  font-style: italic;
}
.kr-architecture {
  margin: 1em 0 1.35em 0;
  page-break-inside: avoid;
  break-inside: avoid;
}
.kr-arch-row {
  display: flex;
  align-items: stretch;
  gap: 0.7em;
  margin: 0.7em 0;
}
.kr-arch-card,
.kr-layer {
  border: 1px solid #cfd8e3;
  border-left: 5px solid $primary;
  background: #f7f9fb;
  padding: 0.75em 0.9em;
  box-sizing: border-box;
  page-break-inside: avoid;
  break-inside: avoid;
}
.kr-arch-card {
  flex: 1 1 0;
  min-width: 0;
}
.kr-arch-arrow {
  flex: 0 0 1.2em;
  align-self: center;
  text-align: center;
  color: $secondary;
  font-family: 'Roboto', sans-serif;
  font-size: 16pt;
  font-weight: 700;
}
.kr-arch-title,
.kr-layer-title {
  font-family: 'Roboto', sans-serif;
  color: $primary;
  font-weight: 600;
  margin: 0 0 0.35em 0;
  line-height: 1.2;
}
.kr-arch-body,
.kr-layer-body {
  font-size: 9.2pt;
  line-height: 1.35;
}
.kr-layer { margin: 0.45em 0; }
.kr-layer ul { margin: 0.35em 0 0.15em 1.1em; }
.kr-layer li { margin: 0.12em 0; }
.kr-layer-foundation { border-left-color: #13365C; }
.kr-layer-data { border-left-color: #0B83A5; }
.kr-layer-process { border-left-color: #27754F; }
.kr-layer-app { border-left-color: #A76209; }
.kr-layer-human { border-left-color: #6E3A78; }
.kr-layer-security { border-left-color: #A23B32; }
.kr-arch-note {
  margin: 0.6em 0 1.1em 0;
  font-size: 9pt;
  color: #4d5965;
  font-style: italic;
}
blockquote { border-left: 5px solid $primary; margin: 1.2em 0; padding: 0.7em 1.2em; background: #f4f7fb; color: $textColor; font-style: normal; }
code { background: #eef2f7; color: #13365C; padding: 0.1em 0.4em; font-family: Consolas, 'Courier New', monospace; font-size: 9.5pt; border-radius: 2px; }
td[class*='g-'] code, .g-bar code { color: #13365C; background: rgba(255,255,255,0.92); }
pre { background: #f4f7fb; padding: 0.9em 1.1em; overflow-x: auto; font-family: Consolas, monospace; font-size: 9pt; border-left: 4px solid $secondary; margin: 1em 0; }
pre { white-space: pre-wrap; word-wrap: break-word; }
hr { border: 0; border-top: 1px solid $lightGrey; margin: 2em 0; }
ul, ol { margin: 0.5em 0 0.8em 1.6em; padding: 0; }
li { margin: 0.25em 0; }
figure, img, svg { max-width: 100%; box-sizing: border-box; }
img { height: auto; display: block; margin: 1em auto; }
figure img { max-width: 82%; max-height: 42vh; }
.page-break { page-break-after: always; break-after: page; }

/* Customer-facing sales-document primitives, lifted from the Kritical playbook style but kept print-safe. */
.callout { border-left: 4px solid $primary; padding: 1em 1.2em; margin: 1em 0; background: #f7f9fb; }
.callout-title { font-family: 'Roboto', sans-serif; font-weight: 600; color: $primary; margin-bottom: 0.25em; }
.callout-red { border-left-color: #c0392b; background: #fdf6f6; }
.callout-red .callout-title { color: #c0392b; }
.callout-green { border-left-color: #278f5f; background: #f4fbf7; }
.callout-green .callout-title { color: #278f5f; }
.callout-blue { border-left-color: $secondary; background: #f3fbfd; }
.callout-blue .callout-title { color: $primary; }
.stat-grid { display: flex; flex-wrap: wrap; gap: 0.7em; margin: 1em 0; }
.stat-item { flex: 1 1 28%; min-width: 160px; padding: 0.8em 1em; background: #f7f9fb; border-left: 3px solid $primary; }
.stat-number { display: block; font-family: 'Roboto', sans-serif; font-size: 18pt; font-weight: 600; color: $primary; line-height: 1.1; }
.stat-label { display: block; font-size: 9pt; color: #4d5965; margin-top: 0.3em; }
.feature-list { list-style: none; margin-left: 0; padding-left: 0; }
.feature-list li { position: relative; padding-left: 1.4em; }
.feature-list li::before { content: "\2713"; position: absolute; left: 0; color: #278f5f; font-weight: 700; }
.script-box, .email-template { background: #f7f9fb; border: 1px solid $lightGrey; padding: 1em 1.2em; margin: 1em 0; font-size: 10pt; }
.script-label, .email-header { font-family: 'Roboto', sans-serif; font-weight: 600; color: $primary; margin-bottom: 0.4em; text-transform: uppercase; letter-spacing: 0.08em; font-size: 8.5pt; }

/* v1.1.6.1 — Cover-page header: tight at top, tight to body */
.kr-cover {
  text-align: center;
  padding: 0;
  margin: 0 0 0.4em 0;
}
.kr-cover-logo {
  max-height: 180px;
  max-width: 50%;
  display: block;
  margin: 0 auto 0.4em auto;
}
.kr-cover-wordmark { font-family: 'Roboto', sans-serif; font-size: 56pt; color: $primary; margin: 0 0 0.2em 0; letter-spacing: 0.02em; font-weight: 500; }
.kr-cover-tagline { font-family: 'Assistant', sans-serif; font-size: 18pt; color: $primary; font-style: italic; margin: 0.4em 0 0.2em 0; font-weight: 500; }
.kr-cover-positioning { font-family: 'Assistant', sans-serif; font-size: 11pt; color: $textColor; opacity: 0.78; margin: 0 0 0.3em 0; text-align: center; }
.kr-cover-contact { font-family: 'Assistant', sans-serif; font-size: 10.5pt; color: $primary; text-align: center; margin: 0.2em 0 0.6em 0; }
.kr-cover-contact a { color: $secondary; text-decoration: none; padding: 0 0.3em; }
.kr-banner-strip {
  display: block;
  width: 100%;
  max-width: 100%;
  height: auto;
  margin: 1em auto 0 auto;
  border-top: 3px solid $primary;
  border-bottom: 3px solid $primary;
}

/* v1.1.7 — Partner-badges band sits as the primary footer, kept inside print-safe page bounds */
.kr-partner-row {
  margin: 1.2em auto 0.7em auto;
  text-align: center;
  background: $primary;
  padding: 0.9em 0.8em 1em 0.8em;
  width: 92%;
  max-width: 92%;
  box-sizing: border-box;
  overflow: hidden;
  page-break-inside: avoid;
}
.kr-partner-label {
  font-family: 'Roboto', sans-serif;
  font-size: 8pt;
  color: #fff;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  margin-bottom: 0.55em;
  opacity: 0.88;
}
.kr-partner-badges {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  align-items: center;
  justify-content: center;
  gap: 0.55em;
  width: 100%;
  max-width: 100%;
  margin: 0 auto;
}
.kr-partner-badge {
  display: block;
  max-height: 26px;
  max-width: 82px;
  width: auto;
  height: auto;
  margin: 0 auto;
  vertical-align: middle;
  object-fit: contain;
  filter: brightness(1.05);
}

/* Footer text band underneath the partner row */
.kr-footer {
  margin-top: 1.5em;
  text-align: center;
  line-height: 1.55;
  page-break-inside: avoid;
  break-inside: avoid;
}
.kr-footer-line { display: block; margin: 0.18em 0; font-size: 8.6pt; color: $textColor; }
.kr-footer-line.kr-corp { opacity: 0.78; }
.kr-footer-line.kr-contact { margin-top: 0.4em; }
.kr-footer-line.kr-contact a { color: $secondary; text-decoration: none; padding: 0 0.3em; }
.kr-tagline { color: $primary; font-size: 10pt; font-weight: 500; }
.kr-corp { color: $textColor; opacity: 0.78; }
.kr-contact { color: $textColor; margin-top: 0.4em; }
.kr-contact a { color: $secondary; text-decoration: none; padding: 0 0.3em; }
.kr-signature { margin-top: 2em; padding: 1.5em 1em 0 1em; border-top: 1px dashed $lightGrey; font-size: 10pt; }

@page { size: A4; margin: 12mm 16mm 18mm 16mm; }
@media print {
  body { max-width: none; padding: 0 4mm; }
  .kr-cover { page-break-after: avoid; }
  h1, h2, h3 { page-break-after: avoid; }
  tr, td, th { page-break-inside: avoid; }
  table.kr-gantt { font-size: 7.6pt; }
  table.kr-gantt th, table.kr-gantt td { padding: 0.32em 0.28em; }
  .doc-meta { font-size: 9.2pt; padding: 0.55em 0.75em; }
  .kr-arch-row { gap: 0.35em; }
  .kr-arch-card, .kr-layer { padding: 0.5em 0.65em; }
  .kr-arch-body, .kr-layer-body { font-size: 8.2pt; }
  .kr-arch-arrow { font-size: 12pt; }
  .kr-partner-row { width: 88%; max-width: 88%; padding: 0.45in 0.25in 0.5in 0.25in; }
  .kr-partner-badges { gap: 0.25in; }
  .kr-partner-badge { max-height: 0.27in; max-width: 0.85in; }
}
"@

    # --- Render Markdown source -> HTML via Pandoc (preferred) -----------------------
    $pandocCmd = $null
    $pandocCommand = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($pandocCommand) {
        $pandocCmd = $pandocCommand.Source
    } else {
        foreach ($pandocCandidate in @(
            (Join-Path $env:LOCALAPPDATA 'Pandoc\pandoc.exe'),
            (Join-Path $env:ProgramFiles 'Pandoc\pandoc.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Pandoc\pandoc.exe')
        )) {
            if ($pandocCandidate -and (Test-Path -LiteralPath $pandocCandidate)) {
                $pandocCmd = $pandocCandidate
                break
            }
        }
    }
    $haveP = $null -ne $pandocCmd
    $haveW = $null -ne (Get-Command wkhtmltopdf -ErrorAction SilentlyContinue)
    $chromePath = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path -LiteralPath $chromePath)) { $chromePath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
    $haveChrome = Test-Path -LiteralPath $chromePath
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    $haveEdge = Test-Path -LiteralPath $edgePath
    $headlessBrowser = if ($haveChrome) { $chromePath } elseif ($haveEdge) { $edgePath } else { $null }

    if (-not $haveP) {
        throw "Pandoc is required for New-KriticalBrandedDocument. Install: winget install --id JohnMacFarlane.Pandoc"
    }

    $intermediateHtml = Join-Path $OutDir ("{0}-intermediate.html" -f $baseName)
    $isHtml = ([IO.Path]::GetExtension($Source)).ToLowerInvariant() -eq '.html'

    # 1.1.10 — Mermaid pre-render: substitute ```mermaid``` blocks with brand-themed PNG images before Pandoc
    $sourceForRender = $Source
    if (-not $isHtml) {
        $mmdcCandidates = @(
            (Join-Path $env:TEMP 'lens-npm-prefix\mmdc.cmd'),
            (Join-Path $env:APPDATA 'npm\mmdc.cmd'),
            'mmdc'
        )
        $mmdcCmd = $mmdcCandidates | Where-Object { $_ -eq 'mmdc' -or (Test-Path -LiteralPath $_) } | Select-Object -First 1
        if ($mmdcCmd) {
            $md = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
            if ($md -match '(?ms)```mermaid\r?\n.*?\r?\n```') {
                $diagramDir = Join-Path $OutDir ("{0}-diagrams" -f $baseName)
                New-Item -ItemType Directory -Force -Path $diagramDir | Out-Null
                $themeJson = Join-Path $diagramDir 'krit-mermaid-theme.json'
                @"
{
  "theme": "base",
  "themeVariables": {
    "primaryColor": "$primary",
    "primaryTextColor": "#FFFFFF",
    "primaryBorderColor": "$primary",
    "lineColor": "$secondary",
    "secondaryColor": "$secondary",
    "tertiaryColor": "$lightGrey",
    "fontFamily": "Roboto, Arial, sans-serif"
  }
}
"@ | Set-Content -LiteralPath $themeJson -Encoding UTF8
                $script:diagIndex = 0
                $pattern = '(?ms)```mermaid\r?\n(.*?)\r?\n```'
                $newMd = [regex]::Replace($md, $pattern, {
                    param($m)
                    $script:diagIndex++
                    $mmdSrc = Join-Path $diagramDir "diagram-$($script:diagIndex).mmd"
                    $pngOut = Join-Path $diagramDir "diagram-$($script:diagIndex).png"
                    $svgOut = Join-Path $diagramDir "diagram-$($script:diagIndex).svg"
                    $m.Groups[1].Value | Set-Content -LiteralPath $mmdSrc -Encoding UTF8
                    try {
                        & $mmdcCmd -i $mmdSrc -o $pngOut -c $themeJson -b white --quiet 2>&1 | Write-Verbose
                    } catch { Write-Warning "mmdc failed on diagram $($script:diagIndex): $_" }
                    if (-not (Test-Path -LiteralPath $pngOut)) {
                        try {
                            & $mmdcCmd -i $mmdSrc -o $svgOut -c $themeJson -b white --quiet 2>&1 | Write-Verbose
                        } catch { Write-Warning "mmdc SVG fallback failed on diagram $($script:diagIndex): $_" }
                    }
                    $diagramOut = if (Test-Path -LiteralPath $pngOut) { $pngOut } elseif (Test-Path -LiteralPath $svgOut) { $svgOut } else { $null }
                    if ($diagramOut) {
                        # URL-encode spaces (and other unsafe chars) so Pandoc + Chrome both follow it
                        $urlPath = ($diagramOut -replace '\\','/')
                        $urlPath = [System.Uri]::EscapeUriString($urlPath)
                        "![]($urlPath)"
                    } else {
                        $m.Value  # leave original block on failure
                    }
                })
                $preRenderedMd = Join-Path $OutDir ("{0}-prerendered.md" -f $baseName)
                Set-Content -LiteralPath $preRenderedMd -Value $newMd -Encoding UTF8
                $sourceForRender = $preRenderedMd
            }
        } else {
            Write-Verbose "mmdc not found; mermaid blocks will render as code"
        }
    }

    # Generate the styled HTML body wrapper
    $bodyHtmlPath = Join-Path $OutDir ("{0}-body.html" -f $baseName)
    if ($isHtml) {
        Copy-Item -LiteralPath $Source -Destination $bodyHtmlPath -Force
    } else {
        & $pandocCmd $sourceForRender -f 'gfm+raw_html' -t html5 -o $bodyHtmlPath 2>&1 | Write-Verbose
    }
    $bodyHtml = Get-Content -LiteralPath $bodyHtmlPath -Raw -Encoding UTF8

    # v1.1.10 — inline local images as data-URIs so standalone HTML/PDF paths cannot break when shared.
    # Pandoc may emit a line break between <img and src=, so this uses dotall matching.
    $localImgPat = '(?is)<img\b([^>]*?)\bsrc=(["''])([^"'']+\.(?:svg|png|jpe?g|webp|gif))\2([^>]*)>'
    $bodyHtml = [regex]::Replace($bodyHtml, $localImgPat, {
        param($m)
        $rawSrc = [System.Net.WebUtility]::HtmlDecode($m.Groups[3].Value)
        if ($rawSrc -match '^(?i:data:|https?://)') { return $m.Value }

        if ($rawSrc -match '^file:') {
            try {
                $local = ([Uri]$rawSrc).LocalPath
            } catch {
                $local = $rawSrc -replace '^file:///',''
            }
        } else {
            $local = [System.Uri]::UnescapeDataString($rawSrc)
        }
        # If relative, resolve against OutDir
        if (-not [IO.Path]::IsPathRooted($local)) { $local = Join-Path $OutDir $local }
        if (Test-Path -LiteralPath $local) {
            try {
                $bytes = [IO.File]::ReadAllBytes($local)
                $mime = & $detectImageMime $bytes $local
                $b64 = [Convert]::ToBase64String($bytes)
                $before = $m.Groups[1].Value
                $after = $m.Groups[4].Value
                return "<img$before src=`"data:$mime;base64,$b64`"$after>"
            } catch {
                Write-Warning "Could not inline image: $local"
            }
        }
        return $m.Value
    })

    $fullHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$($entity.tradeName) - $CustomerName - $DocumentTitle</title>
<meta name="author" content="$($messaging.directorName)">
<meta name="generator" content="Kritical.PS.OmniFramework / New-KriticalBrandedDocument">
<style>$css</style>
</head>
<body>
$headerHtml
$bodyHtml
$footerHtml
$(if ($sigDataHtml) { "<div class='kr-signature'>$sigDataHtml</div>" })
</body>
</html>
"@

    Set-Content -LiteralPath $intermediateHtml -Value $fullHtml -Encoding UTF8
    Remove-Item -LiteralPath $bodyHtmlPath -ErrorAction SilentlyContinue

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    # --- HTML output -------------------------------------------------------------
    if ($Format -contains 'HTML') {
        $htmlOut = Join-Path $OutDir ("{0}.html" -f $baseName)
        Copy-Item -LiteralPath $intermediateHtml -Destination $htmlOut -Force
        $results.Add([pscustomobject]@{ Format='HTML'; Path=$htmlOut; Engine='pandoc+css'; Size=(Get-Item $htmlOut).Length })
    }

    # --- PDF output --------------------------------------------------------------
    if ($Format -contains 'PDF') {
        $pdfOut = Join-Path $OutDir ("{0}.pdf" -f $baseName)
        if ($haveW) {
            & wkhtmltopdf --enable-local-file-access --quiet $intermediateHtml $pdfOut 2>&1 | Write-Verbose
            $engine = 'wkhtmltopdf'
        } elseif ($headlessBrowser) {
            $absUri = ([Uri]$intermediateHtml).AbsoluteUri
            & $headlessBrowser --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$pdfOut" $absUri 2>&1 | Write-Verbose
            $engine = if ($chromePath -eq $headlessBrowser) { 'chrome-headless' } else { 'edge-headless' }
        } else {
            Write-Warning "No PDF engine available (wkhtmltopdf / Chrome / Edge). Skipping PDF for $baseName."
            $engine = $null
        }
        if ($engine -and (Test-Path -LiteralPath $pdfOut)) {
            $results.Add([pscustomobject]@{ Format='PDF'; Path=$pdfOut; Engine=$engine; Size=(Get-Item $pdfOut).Length })
        }
    }

    # --- DOCX output (via Pandoc --reference-doc) --------------------------------
    if ($Format -contains 'DOCX') {
        $docxOut = Join-Path $OutDir ("{0}.docx" -f $baseName)
        $referenceDoc = $null
        if ($brandRoot) {
            $candidate = Join-Path $brandRoot 'Kritical-BaseTemplate-CURRENT.docx'
            if (Test-Path -LiteralPath $candidate) { $referenceDoc = $candidate }
        }
        $pargs = @(
            $sourceForRender
            '-f', 'gfm+raw_html'
            '-t', 'docx'
            '--metadata', "title=$CustomerName - $DocumentTitle"
            '--metadata', "author=$($messaging.directorName)"
            '-o', $docxOut
        )
        if ($referenceDoc) { $pargs += '--reference-doc'; $pargs += $referenceDoc }
        & $pandocCmd @pargs 2>&1 | Write-Verbose
        if (Test-Path -LiteralPath $docxOut) {
            $engine = if ($referenceDoc) { "pandoc+reference-doc" } else { "pandoc (no template)" }
            $results.Add([pscustomobject]@{ Format='DOCX'; Path=$docxOut; Engine=$engine; Size=(Get-Item $docxOut).Length })
        }
    }

    # --- Cleanup intermediate ----------------------------------------------------
    Remove-Item -LiteralPath $intermediateHtml -ErrorAction SilentlyContinue

    [pscustomobject]@{
        Source          = (Resolve-Path -LiteralPath $Source).Path
        OutDir          = (Resolve-Path -LiteralPath $OutDir).Path
        CustomerName    = $CustomerName
        DocumentTitle   = $DocumentTitle
        BaseName        = $baseName
        BrandSpecSource = if ($spec.PSObject.Properties['_sourcePath']) { $spec._sourcePath } else { 'fallback' }
        Outputs         = @($results)
        RenderedAtUtc   = (Get-Date).ToUniversalTime()
    }
}
