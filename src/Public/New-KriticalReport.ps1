function New-KriticalHtmlReport {
    <#
    .SYNOPSIS
        Builds a Kritical-branded HTML report from arbitrary data using PSWriteHTML.

    .DESCRIPTION
        Default-render conventions: Kritical banner ASCII at the top in a <pre>
        block, then a header row with title + timestamp + Kritical hotline + URL,
        then per-section table renders. Falls back to a minimal hand-rolled HTML
        when PSWriteHTML is not installed.

    .EXAMPLE
        $data = Get-KriticalToolInventory
        New-KriticalHtmlReport -Title 'Tool Inventory' -Section @{ Tools = $data } -OutFile C:\drop\inv.html

    .NOTES
        Author: Joshua Finley - Kritical Pty Ltd
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]    $Title,
        [Parameter(Mandatory)] [hashtable] $Section,
        [Parameter(Mandatory)] [string]    $OutFile,
        [string] $Subtitle,
        [switch] $NoOpen
    )
    $bannerStr = Get-KriticalBanner -Title $Title
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm K')

    # Ensure parent directory exists (PSWriteHTML's Save-HTML does NOT auto-create it; falls back to %TEMP% if missing).
    $parentDir = Split-Path -Parent $OutFile
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Get-Module -ListAvailable -Name PSWriteHTML) {
        Import-Module PSWriteHTML -Force -ErrorAction Stop
        # PSWriteHTML's New-HTML expects -Content (positional ScriptBlock), not -ScriptBlock.
        $content = {
            New-HTMLSection -HeaderText 'Kritical Brand Banner' -Content {
                New-HTMLText -Text $bannerStr -FontFamily Consolas -FontSize 10 -Color DarkBlue
            }
            New-HTMLSection -HeaderText "$Title - $ts" -Content {
                New-HTMLText -Text 'A Seriously Kritical(TM) Production | kritical.net | +61 1300 274 655' -Color DarkBlue
                if ($Subtitle) { New-HTMLText -Text $Subtitle -FontStyle Italic }
            }
            foreach ($key in $Section.Keys) {
                $val = $Section[$key]
                New-HTMLSection -HeaderText $key -Content {
                    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                        New-HTMLTable -DataTable $val -HideFooter
                    } else {
                        New-HTMLText -Text ($val | Out-String)
                    }
                }
            }
        }
        New-HTML -TitleText "Kritical: $Title" -FilePath $OutFile -ShowHTML:(-not $NoOpen.IsPresent) -Online -Content $content
    } else {
        # Minimal hand-rolled fallback
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("<!DOCTYPE html><html><head><meta charset='utf-8'><title>Kritical: $Title</title>")
        [void]$sb.Append("<style>body{font-family:Segoe UI,Arial,sans-serif;background:#fff;color:#13365C;margin:30px}h1{color:#13365C}pre.banner{background:#f6f8fa;padding:14px;font:11px Consolas,monospace;color:#13365C;white-space:pre}.kt{margin:20px 0}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:6px 8px}th{background:#13365C;color:#fff;text-align:left}</style></head><body>")
        [void]$sb.Append("<pre class='banner'>" + [System.Net.WebUtility]::HtmlEncode($bannerStr) + "</pre>")
        [void]$sb.Append("<h1>$([System.Net.WebUtility]::HtmlEncode($Title))</h1>")
        [void]$sb.Append("<p><b>Generated</b> $ts &mdash; <b>kritical.net</b> &mdash; +61 1300 274 655</p>")
        foreach ($key in $Section.Keys) {
            $val = $Section[$key]
            [void]$sb.Append("<div class='kt'><h2>$([System.Net.WebUtility]::HtmlEncode($key))</h2>")
            if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                $rows = @($val)
                if ($rows.Count -gt 0) {
                    $props = ($rows[0].PSObject.Properties.Name)
                    [void]$sb.Append('<table><thead><tr>')
                    foreach ($p in $props) { [void]$sb.Append("<th>$p</th>") }
                    [void]$sb.Append('</tr></thead><tbody>')
                    foreach ($r in $rows) {
                        [void]$sb.Append('<tr>')
                        foreach ($p in $props) { [void]$sb.Append("<td>$([System.Net.WebUtility]::HtmlEncode([string]$r.$p))</td>") }
                        [void]$sb.Append('</tr>')
                    }
                    [void]$sb.Append('</tbody></table>')
                } else { [void]$sb.Append('<p>(empty)</p>') }
            } else {
                [void]$sb.Append('<pre>' + [System.Net.WebUtility]::HtmlEncode([string]$val) + '</pre>')
            }
            [void]$sb.Append('</div>')
        }
        [void]$sb.Append('</body></html>')
        New-Item -ItemType Directory -Path (Split-Path -Parent $OutFile) -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -LiteralPath $OutFile -Value ($sb.ToString()) -Encoding UTF8
    }

    [pscustomobject]@{
        Title       = $Title
        OutFile     = (Resolve-Path -LiteralPath $OutFile).Path
        Sections    = $Section.Count
        Renderer    = if (Get-Module PSWriteHTML) { 'PSWriteHTML' } else { 'minimal-html-fallback' }
    }
}

function New-KriticalExcelReport {
    <#
    .SYNOPSIS
        Builds a Kritical-branded .xlsx report from one or more datasets using ImportExcel.
    .EXAMPLE
        New-KriticalExcelReport -Title 'Tool Inventory' -Sheet @{ Tools = (Get-KriticalToolInventory) } -OutFile C:\drop\inv.xlsx
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]    $Title,
        [Parameter(Mandatory)] [hashtable] $Sheet,
        [Parameter(Mandatory)] [string]    $OutFile
    )
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        throw "ImportExcel module not installed. Run Import-KriticalFoundation first."
    }
    Import-Module ImportExcel -Force -ErrorAction Stop
    New-Item -ItemType Directory -Path (Split-Path -Parent $OutFile) -Force -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    # Banner sheet
    $bannerLines = (Get-KriticalBanner -Title $Title).Split("`n")
    $bannerData = @(0..($bannerLines.Count-1) | ForEach-Object { [pscustomobject]@{ Line = $bannerLines[$_].TrimEnd() } })
    $bannerData | Export-Excel -Path $OutFile -WorksheetName 'Kritical' -AutoSize -BoldTopRow -Title "Kritical: $Title" -TitleSize 14 -TitleBold
    foreach ($k in $Sheet.Keys) {
        $val = $Sheet[$k]
        if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
            @($val) | Export-Excel -Path $OutFile -WorksheetName $k -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -TableName ($k -replace '[^A-Za-z0-9_]','_')
        } else {
            @([pscustomobject]@{ Value = ($val | Out-String) }) | Export-Excel -Path $OutFile -WorksheetName $k -AutoSize
        }
    }
    [pscustomobject]@{
        Title    = $Title
        OutFile  = (Resolve-Path -LiteralPath $OutFile).Path
        Sheets   = ($Sheet.Keys.Count + 1)
        Renderer = 'ImportExcel'
    }
}
