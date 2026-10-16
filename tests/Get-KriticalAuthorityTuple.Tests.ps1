#requires -Modules Pester
<#
    Pester 5 contract tests for src\Public\Get-KriticalAuthorityTuple.ps1
    Design: vendor-profile-design-20261016 DESIGN.md, section 2 (resolver contract) and section 4 task 6.

    The REAL function is dot-sourced. Invoke-RestMethod is mocked; no network is used.
    All values are fake (consumer 'pax8', environment 'dev', profile 'b', bearer 'FAKE-BEARER-TOKEN-T6').
    Expected state before implementation: several tests RED (the -Profile parameter does not exist yet).
#>

BeforeAll {
    $script:FunctionPath = Join-Path $PSScriptRoot '..\src\Public\Get-KriticalAuthorityTuple.ps1'
    . $script:FunctionPath

    $script:BaseUri = 'https://es.invalid/mcp'
    $script:Token   = 'FAKE-BEARER-TOKEN-T6'

    function New-FakeMcpResponse {
        param([Parameter(Mandatory)][hashtable] $Tuple)
        $json = $Tuple | ConvertTo-Json -Depth 8 -Compress
        [pscustomobject]@{ result = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = $json }) } }
    }
}

AfterAll {
    Remove-Variable -Name KritT6Body -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-KriticalAuthorityTuple vendor-profile contract (design section 2, task 6)' {

    Context 'Command under test' {
        # Item 1
        It 'item 1: the real function is loaded from src\Public and the command exists' {
            $cmd = Get-Command -Name Get-KriticalAuthorityTuple -ErrorAction Stop
            $cmd.CommandType | Should -BeExactly 'Function'
            Test-Path -LiteralPath $script:FunctionPath | Should -BeTrue
        }
    }

    Context 'Request arguments sent to get_effective_authority_tuple' {

        # Item 2 (transport is mocked; nothing reaches a real endpoint)
        It 'item 2: the only transport used is the mocked Invoke-RestMethod, aimed at the supplied base URI' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://es.invalid/mcp' }
        }

        # Item 3
        It 'item 3: -Profile b is sent as profile = b beside consumer and environment' {
            $global:KritT6Body = $null
            Mock Invoke-RestMethod {
                param($Uri, $Method, $ContentType, $Headers, $Body)
                $global:KritT6Body = [string]$Body
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; profileKey = 'b'; rows = @() }
            }
            $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -Profile b -BaseUri $script:BaseUri -BearerToken $script:Token
            $global:KritT6Body | Should -Not -BeNullOrEmpty
            $req = $global:KritT6Body | ConvertFrom-Json -Depth 16
            $req.params.name | Should -BeExactly 'get_effective_authority_tuple'
            $req.params.arguments.consumer    | Should -BeExactly 'pax8'
            $req.params.arguments.environment | Should -BeExactly 'dev'
            $req.params.arguments.profile     | Should -BeExactly 'b'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 4
        It 'item 4: without -Profile the arguments carry no profile value (absent or null); legacy call shape kept' {
            $global:KritT6Body = $null
            Mock Invoke-RestMethod {
                param($Uri, $Method, $ContentType, $Headers, $Body)
                $global:KritT6Body = [string]$Body
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            $global:KritT6Body | Should -Not -BeNullOrEmpty
            $req = $global:KritT6Body | ConvertFrom-Json -Depth 16
            $req.params.arguments.consumer    | Should -BeExactly 'pax8'
            $req.params.arguments.environment | Should -BeExactly 'dev'
            $hasProfile = ($req.params.arguments.PSObject.Properties.Name -contains 'profile') -and ($null -ne $req.params.arguments.profile)
            $hasProfile | Should -BeFalse
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'Response handling' {

        # Item 5
        It 'item 5: a GREEN response carrying profileKey b returns an object with ProfileKey = b' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{
                    status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; profileKey = 'b'
                    rows = @(@{ policy_key = 'client.pax8.dev.client_id_env'; value_kind = 'env-var-name'; value_text = 'FAKE_CLIENT_ID_ENV_B'; scope = 'dev'; description = 'fake'; source_ref = 'fake'; updated_utc = '2026-10-16T00:00:00Z' })
                }
            }
            $result = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -Profile b -BaseUri $script:BaseUri -BearerToken $script:Token
            ($result.PSObject.Properties.Name -ccontains 'ProfileKey') | Should -BeTrue
            $result.ProfileKey | Should -BeExactly 'b'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 5 (design-named companion fields, exact PascalCase names as written in the design)
        It 'item 5b: ProfileKind, ParentProfileKey, VendorClass and CandidateProfiles are exposed on the result' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{
                    status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; profileKey = 'b'
                    profileKind = 'profile'; parentProfileKey = $null; vendorClass = 'distributor'; candidateProfiles = @('b')
                    rows = @()
                }
            }
            $result = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -Profile b -BaseUri $script:BaseUri -BearerToken $script:Token
            $names = $result.PSObject.Properties.Name
            ($names -ccontains 'ProfileKind') | Should -BeTrue
            ($names -ccontains 'ParentProfileKey') | Should -BeTrue
            ($names -ccontains 'VendorClass') | Should -BeTrue
            ($names -ccontains 'CandidateProfiles') | Should -BeTrue
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 6
        It 'item 6: effectiveStatus RED with PROFILE_AMBIGUOUS throws' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'RED'; code = 'PROFILE_AMBIGUOUS'; candidateProfiles = @('a', 'b'); consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            { Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token } | Should -Throw '*RED*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 6 (message content)
        It 'item 6b: the RED/PROFILE_AMBIGUOUS throw message names both the status and the code' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'RED'; code = 'PROFILE_AMBIGUOUS'; candidateProfiles = @('a', 'b'); consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            $err = $null
            try { $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token }
            catch { $err = $_.Exception.Message }
            $err | Should -Not -BeNullOrEmpty
            $err | Should -CMatch 'RED'
            $err | Should -CMatch 'PROFILE_AMBIGUOUS'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 7
        It 'item 7: request profile b but response profileKey a throws (fail-closed rule 5)' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; profileKey = 'a'; rows = @() }
            }
            $err = $null
            try { $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -Profile b -BaseUri $script:BaseUri -BearerToken $script:Token }
            catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            # A parameter-binding failure (the -Profile parameter is missing) is not the fail-closed throw under test.
            $err.FullyQualifiedErrorId | Should -Not -CMatch 'NamedParameterNotFound'
            $err.Exception.Message | Should -CMatch 'profile'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'S20 vacuous-run guards' {

        # Item 8 (positive guard: a run that reaches the transport is counted)
        It 'item 8: a call that reaches the transport is counted, so a run that never calls it cannot pass' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 8 (negative control: the guard itself must fail when the transport was never called)
        It 'item 8 negative control: the invocation assertion FAILS when the transport was never called' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; rows = @() }
            }
            { Should -Invoke Invoke-RestMethod -Times 1 -Exactly } | Should -Throw
        }
    }

    Context 'Input validation' {

        # Item 9
        It 'item 9: -Profile Bad Profile! (violates ^[a-z0-9-]{1,60}$) is rejected before any transport call' {
            Mock Invoke-RestMethod {
                New-FakeMcpResponse -Tuple @{ status = 'ok'; effectiveStatus = 'GREEN'; consumer = 'pax8'; environment = 'dev'; profileKey = 'b'; rows = @() }
            }
            $err = $null
            try { $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -Profile 'Bad Profile!' -BaseUri $script:BaseUri -BearerToken $script:Token }
            catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            # Parameter ValidatePattern failures carry the ParameterArgumentValidationError id; an unknown parameter does not.
            $err.FullyQualifiedErrorId | Should -CMatch 'ParameterArgumentValidationError'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
    }
}
