<#
.SYNOPSIS
    Kritical.PS.OmniFramework - Kritical multi-OS PowerShell foundation.

.DESCRIPTION
    Single Import-Module brings up the Kritical PowerShell foundation:
      - PSFramework (logging, configuration)
      - PSSharedGoods (shared utilities; disambiguated from psutil)
      - PSWriteHTML (HTML reports)
      - ImportExcel (Excel I/O)
      - Optional: PSWriteOffice / PSWriteWord / PSWritePDF when present
    Plus Kritical primitives:
      - Multi-OS detection (Windows/macOS/Linux + distro + arch + privilege)
      - FHS/LSB-aware tool inventory across every standard path per OS
      - Kritical-branded report templates and the canonical brand banner

.AUTHOR
    Joshua Finley - Kritical Pty Ltd - https://kritical.net
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source Private then Public
$here = Split-Path -Parent $PSCommandPath
foreach ($dir in 'Private','Public') {
    $folder = Join-Path $here $dir
    if (Test-Path -LiteralPath $folder) {
        Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
            . $_.FullName
        }
    }
}

Export-ModuleMember -Function @(
    'Write-KriticalBanner', 'Get-KriticalBanner',
    'Get-KriticalPlatform', 'Test-KriticalIsAdmin', 'Test-KriticalIsElevated',
    'Get-KriticalToolInventory', 'Find-KriticalTool', 'Test-KriticalToolPresent',
    'Import-KriticalFoundation', 'Get-KriticalFoundationStatus',
    'Write-KriticalLog', 'Start-KriticalLogSession', 'Stop-KriticalLogSession',
    'New-KriticalHtmlReport', 'New-KriticalExcelReport',
    'Resolve-KriticalRepoRoot', 'Get-KriticalConfig', 'Get-KriticalProject', 'Get-KriticalPath',
    'Test-KriticalSecretsLoaded',
    # 1.1.0 - Brand pipeline
    'Get-KriticalBrandSpec', 'New-KriticalBrandedDocument',
    # 1.1.8 - Programmatic markdown linter
    'Invoke-KriticalMdLint',
    # 1.1.12 - OneDrive sharing-link helper (Microsoft Graph delegated auth)
    'New-KriticalOneDriveShareLink',
    # 1.1.13 - OneDrive share-permission management
    'Get-KriticalOneDriveShareLinkPermissions',
    'Add-KriticalOneDriveShareLinkRecipients',
    'Remove-KriticalOneDriveShareLinkPermission',
    'Set-KriticalOneDriveShareLinkPermission'
)
