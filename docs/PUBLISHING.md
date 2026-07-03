# Kritical.PS.OmniFramework — Publishing

Author: Joshua Finley — Kritical Pty Ltd

## Pre-flight (every release)

1. **Pester suite green**: `tools\Publish-KriticalOmniFramework.ps1` runs this automatically; or `tests\Invoke-AllTests.ps1` manually.
2. **`Test-ModuleManifest src\Kritical.PS.OmniFramework.psd1`** passes.
3. **No secret leaks** in the repo (the publish helper's doc + secrets check is best-effort; manually grep too).
4. **Banner asset identical to canonical** (`Kritical-Branding\public\KriticalLogo.txt`).
5. **Author/Company stamp**: `Author = 'Joshua Finley'`, `CompanyName = 'Kritical Pty Ltd'`.
6. **Version bumped + ReleaseNotes added** in the manifest.

## Publish helper

```powershell
& "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.PS.OmniFramework\tools\Publish-KriticalOmniFramework.ps1"
```

Runs the full gate (docs check + test run + manifest validate) then stages + publishes to PSGallery.

## Manual fallback

```powershell
$apiKey = (Get-Content "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos\psgallery-api-key.txt" -Raw).Trim()
$repo = "$env:USERPROFILE\OneDrive - Kritical Pty Ltd\Github\Kritical.PS.OmniFramework"
$stage = Join-Path $env:LOCALAPPDATA 'Kritical\Kritical.PS.OmniFramework\publish-staging\Kritical.PS.OmniFramework'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -Recurse -Force "$repo\src\*" $stage
Publish-Module -Path $stage -NuGetApiKey $apiKey -Verbose
```

## GitHub release zip

```powershell
$out = Join-Path $env:LOCALAPPDATA 'Kritical\Kritical.PS.OmniFramework\release\Kritical.PS.OmniFramework-1.0.0.zip'
$stage = "$env:LOCALAPPDATA\Kritical\Kritical.PS.OmniFramework\zip-staging"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -Recurse -Force "$repo\src\*" $stage
Copy-Item -Force "$repo\README.md","$repo\LICENSE","$repo\CONTRIBUTING.md" $stage
Copy-Item -Recurse -Force "$repo\docs" $stage
Push-Location $stage
try { Compress-Archive -Path .\* -DestinationPath $out -Force } finally { Pop-Location }
gh release create v1.0.0 $out -t 'Kritical.PS.OmniFramework 1.0.0' -n 'Kritical multi-OS PowerShell foundation. Author: Joshua Finley - Kritical Pty Ltd.'
```

## Rollback

`Unpublish-Module -Name Kritical.PS.OmniFramework -RequiredVersion 1.0.0 -NuGetApiKey $apiKey` (within 90 days), or publish a patch bumping the broken function.
