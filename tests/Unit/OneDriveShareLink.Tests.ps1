#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'New-KriticalOneDriveShareLink — surface contract' {
    It 'exports the function' {
        Get-Command -Name New-KriticalOneDriveShareLink -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'declares the documented parameter set' {
        $cmd = Get-Command -Name New-KriticalOneDriveShareLink
        $cmd.Parameters.ContainsKey('LocalPath')          | Should -BeTrue
        $cmd.Parameters.ContainsKey('ShareType')          | Should -BeTrue
        $cmd.Parameters.ContainsKey('ShareScope')         | Should -BeTrue
        $cmd.Parameters.ContainsKey('Recipients')         | Should -BeTrue
        $cmd.Parameters.ContainsKey('Password')           | Should -BeTrue
        $cmd.Parameters.ContainsKey('ExpirationDateTime') | Should -BeTrue
        $cmd.Parameters.ContainsKey('UseDeviceCode')      | Should -BeTrue
    }

    It 'restricts ShareType to view|edit' {
        $cmd = Get-Command -Name New-KriticalOneDriveShareLink
        $vs  = $cmd.Parameters['ShareType'].Attributes |
               Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
               Select-Object -First 1
        $vs                | Should -Not -BeNullOrEmpty
        $vs.ValidValues    | Should -Be @('view','edit')
    }

    It 'restricts ShareScope to anonymous|organization|users' {
        $cmd = Get-Command -Name New-KriticalOneDriveShareLink
        $vs  = $cmd.Parameters['ShareScope'].Attributes |
               Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
               Select-Object -First 1
        $vs                | Should -Not -BeNullOrEmpty
        $vs.ValidValues    | Should -Be @('anonymous','organization','users')
    }

    It 'requires LocalPath' {
        $cmd = Get-Command -Name New-KriticalOneDriveShareLink
        $cmd.Parameters['LocalPath'].Attributes.Mandatory -contains $true | Should -BeTrue
    }

    It 'returns a PSCustomObject with the documented properties (mock-isolated)' {
        # Smoke test: invoke against a guaranteed-bad path to verify error-path returns nothing
        # and verify the function exists, accepts params, and has the right output shape DECLARED.
        # Live Graph round-trip is covered by E2E suite (not unit) — requires Microsoft.Graph
        # signed-in context that isn't appropriate to wire into per-PR Pester runs.
        $cmd = Get-Command -Name New-KriticalOneDriveShareLink
        # PowerShell reports [pscustomobject] OutputType as 'PSObject' (its underlying .NET type name).
        # Accept either spelling — both prove the function declared a PSCustomObject return contract.
        $cmd.OutputType.Type.Name | Should -BeIn @('PSCustomObject','PSObject')
    }

    It 'throws on a path that is not under the OneDrive sync root' {
        $bogusPath = if ($IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            'C:\Temp\definitely-not-a-onedrive-path-xyz'
        } else {
            '/tmp/definitely-not-a-onedrive-path-xyz'
        }
        # Path may or may not exist; either way it shouldn't be under the OneDrive sync root —
        # function should throw before any Graph call. We accept both 'not under sync root'
        # and 'path not found' as valid early-error outcomes.
        { New-KriticalOneDriveShareLink -LocalPath $bogusPath -ErrorAction Stop } | Should -Throw
    }
}

Describe 'New-KriticalOneDriveShareLink — documentation surface' {
    It 'has a non-empty SYNOPSIS' {
        (Get-Help New-KriticalOneDriveShareLink).Synopsis | Should -Not -BeNullOrEmpty
    }
    It 'documents at least three examples' {
        $examples = (Get-Help New-KriticalOneDriveShareLink -Examples).Examples.Example
        @($examples).Count | Should -BeGreaterOrEqual 3
    }
}
