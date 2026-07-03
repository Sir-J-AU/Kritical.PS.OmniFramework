<#
.SYNOPSIS
    Kritical.PS.OmniFramework full test runner. Pester 5+. Output OUT of repo by default.
.AUTHOR
    Joshua Finley - Kritical Pty Ltd
#>
[CmdletBinding()]
param(
    [switch] $NoBanner,
    [string] $OutputDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
$repo = Split-Path -Parent $here
Import-Module (Join-Path $repo 'src\Kritical.PS.OmniFramework.psm1') -Force

if (-not $NoBanner.IsPresent) { Write-KriticalBanner -Title 'Test Runner' }

$pester = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    Write-Host 'Installing Pester 5...' -ForegroundColor Yellow
    Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
}
Import-Module Pester -MinimumVersion 5.5.0 -Force

if (-not $OutputDir) { $OutputDir = Join-Path $env:LOCALAPPDATA 'Kritical\Kritical.PS.OmniFramework\test-output' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Write-Host ("Test artefacts -> " + $OutputDir) -ForegroundColor DarkGray
$utc = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')

$conf = New-PesterConfiguration
$conf.Run.Path = @((Join-Path $here 'Unit'))
$conf.Output.Verbosity = 'Detailed'
$conf.TestResult.Enabled = $true
$conf.TestResult.OutputPath = (Join-Path $OutputDir "results-$utc.xml")
$conf.TestResult.OutputFormat = 'NUnitXml'
$conf.Run.PassThru = $true

$result = Invoke-Pester -Configuration $conf
$summary = [pscustomobject]@{
    UtcStamp = $utc; Total=$result.TotalCount; Passed=$result.PassedCount; Failed=$result.FailedCount
    Skipped=$result.SkippedCount; Duration=$result.Duration; Result=$result.Result
}
$summary | Format-List | Out-String | Write-Host
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir "summary-$utc.json")

if ($result.Result -ne 'Passed') { Write-Host "FAIL - $($result.FailedCount) tests failed." -ForegroundColor Red; exit 1 }
Write-Host "PASS - $($result.PassedCount) tests; $($result.SkippedCount) skipped; $($result.Duration) total." -ForegroundColor Green
exit 0
