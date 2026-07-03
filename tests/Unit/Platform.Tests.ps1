#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'Get-KriticalPlatform' {
    It 'returns a PSCustomObject with Family / DistroId / Architecture / IsAdmin' {
        $p = Get-KriticalPlatform
        $p | Should -Not -BeNullOrEmpty
        $p.Family       | Should -BeIn @('Windows','macOS','Linux','Unknown')
        $p.DistroId     | Should -Not -BeNullOrEmpty
        $p.Architecture | Should -BeIn @('X64','Arm64','X86','Arm','Unknown')
        $p.IsAdmin      | Should -BeOfType [bool]
        $p.HostName     | Should -Not -BeNullOrEmpty
        $p.PSEdition    | Should -BeIn @('Desktop','Core')
        $p.PSVersion    | Should -Not -BeNullOrEmpty
    }
    It 'returns Windows on a Windows host (this test machine is Windows)' {
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            (Get-KriticalPlatform).Family | Should -Be 'Windows'
        }
    }
}

Describe 'Test-KriticalIsAdmin / Test-KriticalIsElevated' {
    It 'returns a boolean and the two helpers agree' {
        $a = Test-KriticalIsAdmin
        $b = Test-KriticalIsElevated
        $a | Should -BeOfType [bool]
        $b | Should -BeOfType [bool]
        $a | Should -Be $b
    }
}
