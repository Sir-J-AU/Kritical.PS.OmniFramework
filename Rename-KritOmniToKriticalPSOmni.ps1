#requires -Version 7.0
<#
.SYNOPSIS
    Renames Krit.OmniFramework -> Kritical.PS.OmniFramework (module name) and
    every `Krit<Verb>` / `Krit<Noun>` primitive prefix to `Kritical<...>`.
    Preserves compound prefixes that already fit the wider Kritical naming
    (KritBrand, KritDeadDrop, KritGraphProp, etc.) by matching only where
    Krit sits directly against a PascalCase word.

.NOTES
    Consumers currently calling `Import-Module Krit.OmniFramework` or any
    `Get-Krit*` cmdlet will need to update their manifests + call sites.
    A PSGallery-side deprecation shim is queued as follow-up wave WAVE-5181.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateSet('Content','Filenames','Both')][string]$Phase = 'Both'
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

$replacements = @(
    # Longest / most specific first
    @{ Pattern = 'Krit\.OmniFramework'; Replacement = 'Kritical.PS.OmniFramework' }
    # Function-prefix flip: any Krit followed by a PascalCase word becomes Kritical<same word>
    # PascalCase word = A-Z followed by lowercase letters (guards against Krit followed by non-name chars)
    @{ Pattern = '\bKrit(?=[A-Z][a-z])';   Replacement = 'Kritical' }
)

$textExtensions = @('.ps1','.psm1','.psd1','.md','.json','.yml','.yaml','.txt','.gitignore')

$stats = [ordered]@{
    Apply=[bool]$Apply; Phase=$Phase; Scanned=0; ContentEdited=0; ContentHits=0
    FilesRenamed=0; PerPattern=@{}; SampleContent=@(); SampleRename=@(); Errors=@()
}
foreach ($r in $replacements) { $stats.PerPattern[$r.Pattern] = 0 }

function Get-RepoFiles {
    Get-ChildItem -Path $repo -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '\\\.git\\' -and
        $_.FullName -notlike '*.bak.*' -and
        $_.Name -ne 'Rename-KritOmniToKriticalPSOmni.ps1'
    }
}

if ($Phase -in @('Content','Both')) {
    Write-Host "== Content ==" -ForegroundColor Cyan
    foreach ($f in Get-RepoFiles) {
        $stats.Scanned++
        if ($textExtensions -notcontains $f.Extension.ToLower()) { continue }
        try {
            $orig = [System.IO.File]::ReadAllText($f.FullName)
            $cur = $orig
            $hits = 0
            foreach ($r in $replacements) {
                $m = [regex]::Matches($cur, $r.Pattern)
                if ($m.Count -gt 0) {
                    $stats.PerPattern[$r.Pattern] += $m.Count
                    $hits += $m.Count
                    $cur = [regex]::Replace($cur, $r.Pattern, $r.Replacement)
                }
            }
            if ($cur -ne $orig) {
                $stats.ContentEdited++
                $stats.ContentHits += $hits
                if ($stats.SampleContent.Count -lt 5) {
                    $stats.SampleContent += $f.FullName.Substring($repo.Length + 1)
                }
                if ($Apply) { [System.IO.File]::WriteAllText($f.FullName, $cur) }
            }
        } catch { $stats.Errors += "$($f.FullName): $_" }
    }
    Write-Host ("  Scanned: {0}  Edited: {1}  Total hits: {2}" -f $stats.Scanned, $stats.ContentEdited, $stats.ContentHits)
    foreach ($k in $stats.PerPattern.Keys) { Write-Host ("    {0,-40} {1}" -f $k, $stats.PerPattern[$k]) }
}

if ($Phase -in @('Filenames','Both')) {
    Write-Host "== Filenames ==" -ForegroundColor Cyan
    $files = Get-RepoFiles | Where-Object { $_.Name -match 'Krit\.OmniFramework|\bKrit[A-Z][a-z]' } |
        Sort-Object { $_.FullName.Length } -Descending
    foreach ($f in $files) {
        $newName = $f.Name
        foreach ($r in $replacements) {
            $newName = [regex]::Replace($newName, $r.Pattern, $r.Replacement)
        }
        if ($newName -ne $f.Name) {
            $stats.FilesRenamed++
            if ($stats.SampleRename.Count -lt 5) {
                $stats.SampleRename += "$($f.Name)  ->  $newName"
            }
            if ($Apply) {
                try {
                    $rel = $f.FullName.Substring($repo.Length + 1).Replace('\','/')
                    $newRel = (Join-Path (Split-Path $rel -Parent) $newName).Replace('\','/')
                    Push-Location $repo
                    try {
                        $null = git mv -- $rel $newRel 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $f.Directory.FullName $newName) -Force
                        }
                    } finally { Pop-Location }
                } catch { $stats.Errors += "$($f.FullName): $_" }
            }
        }
    }
    Write-Host ("  Renamed: {0}" -f $stats.FilesRenamed)
    $stats.SampleRename | ForEach-Object { Write-Host "    $_" }
}

if ($stats.Errors.Count -gt 0) {
    Write-Warning ("{0} errors:" -f $stats.Errors.Count)
    $stats.Errors | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
}
