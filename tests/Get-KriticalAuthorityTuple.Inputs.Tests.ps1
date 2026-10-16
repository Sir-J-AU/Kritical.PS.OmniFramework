#requires -Modules Pester
<#
    Pester contract tests for the -Consumer and -Environment input rules of
    src\Public\Get-KriticalAuthorityTuple.ps1.
    Design: vendor-profile-design-20261016 DESIGN.md, section 2 "Inputs":
      consumer    ^[A-Za-z0-9._-]{1,80}$
      environment ^[A-Za-z0-9-]{1,80}$
      profile     ^[a-z0-9-]{1,60}$   (covered by the existing Get-KriticalAuthorityTuple.Tests.ps1)

    The REAL function is dot-sourced. Invoke-RestMethod is mocked; no network is used.
    All values are fake. Bearer token is 'FAKE-BEARER-TOKEN-T6B'.

    Expected state before implementation (RED): items 2, 4 and 7 fail because the function still
    carries ValidateSet attributes on -Consumer and -Environment. Items 5 and 6 pass today only
    because ValidateSet rejects the same values; they are kept as regression guards for the
    pattern rule that replaces the ValidateSet.
#>

BeforeAll {
    $script:FunctionPath = Join-Path $PSScriptRoot '..\src\Public\Get-KriticalAuthorityTuple.ps1'
    . $script:FunctionPath

    $script:BaseUri = 'https://es.invalid/mcp'
    $script:Token   = 'FAKE-BEARER-TOKEN-T6B'

    function New-FakeMcpResponse {
        param([Parameter(Mandatory)][hashtable] $Tuple)
        $json = $Tuple | ConvertTo-Json -Depth 8 -Compress
        [pscustomobject]@{ result = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = $json }) } }
    }

    # Echo mock: returns a GREEN document whose consumer and environment echo the request.
    # The request is read from the Body the function actually sent, so a mangled argument fails the function's own match check.
    function New-EchoMcpResponse {
        param([Parameter(Mandatory)][string] $Body)
        $req = $Body | ConvertFrom-Json -Depth 16
        $c = [string]$req.params.arguments.consumer
        $e = [string]$req.params.arguments.environment
        New-FakeMcpResponse -Tuple @{
            status = 'ok'; effectiveStatus = 'GREEN'; consumer = $c; environment = $e
            rows = @(@{ policy_key = "client.$c.$e.client_id_env"; value_kind = 'env-var-name'; value_text = 'FAKE_ID_ENV'; scope = $e; description = 'fake'; source_ref = 'fake'; updated_utc = '2026-10-17T00:00:00Z' })
        }
    }
}

AfterAll {
    Remove-Variable -Name KritT6bEcho -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-KriticalAuthorityTuple consumer and environment input rules (design section 2)' {

    Context 'Command under test' {

        # Item 1
        It 'item 1: the real function is loaded from src\Public, and an echo GREEN mock returns a GREEN tuple for pax8/dev' {
            $cmd = Get-Command -Name Get-KriticalAuthorityTuple -ErrorAction Stop
            $cmd.CommandType | Should -BeExactly 'Function'
            Test-Path -LiteralPath $script:FunctionPath | Should -BeTrue

            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $result = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            $result.status          | Should -BeExactly 'ok'
            $result.effectiveStatus | Should -BeExactly 'GREEN'
            $result.consumer        | Should -BeExactly 'pax8'
            $result.environment     | Should -BeExactly 'dev'
            $result.rows[0].policy_key | Should -BeExactly 'client.pax8.dev.client_id_env'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'Item 2: new consumers are accepted' {

        # Item 2
        It 'item 2: consumer <_> is accepted, transport called once, request carries the exact string' -ForEach @('dickerB2b', 'crowdStrike') {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $result = Get-KriticalAuthorityTuple -Consumer $_ -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            $result.consumer | Should -BeExactly $_
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                ((([string]$Body) | ConvertFrom-Json -Depth 16).params.arguments.consumer) -ceq $_
            }
        }
    }

    Context 'Item 3: existing consumers still accepted (regression)' {

        # Item 3
        It 'item 3: existing consumer <_> is still accepted, transport called once' -ForEach @('pax8', 'd365bc', 'environment-switcher', 'document-renderer') {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $result = Get-KriticalAuthorityTuple -Consumer $_ -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            $result.consumer | Should -BeExactly $_
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                ((([string]$Body) | ConvertFrom-Json -Depth 16).params.arguments.consumer) -ceq $_
            }
        }
    }

    Context 'Item 4: child-environment ids are accepted' {

        # Item 4
        It 'item 4: environment <_> is accepted, transport called once, request carries the exact string' -ForEach @('dev-tenant-a', 'DEV2') {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $result = Get-KriticalAuthorityTuple -Consumer pax8 -Environment $_ -BaseUri $script:BaseUri -BearerToken $script:Token
            $result.environment | Should -BeExactly $_
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                ((([string]$Body) | ConvertFrom-Json -Depth 16).params.arguments.environment) -ceq $_
            }
        }
    }

    Context 'Item 5: invalid consumers are rejected before any transport call' {

        # Item 5
        It 'item 5: consumer <Name> is rejected by parameter validation with zero transport calls' -ForEach @(
            @{ Name = 'empty';         Value = '' }
            @{ Name = 'with space';    Value = 'bad consumer' }
            @{ Name = 'with slash';    Value = 'a/b' }
            @{ Name = 'with semicolon';Value = 'x;drop' }
            @{ Name = '81 characters'; Value = ('a' * 81) }
            @{ Name = 'trailing newline (regex $ matches before a final LF)'; Value = "pax8`n" }
            @{ Name = 'embedded newline'; Value = "pa`nx8" }
        ) {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $err = $null
            try { $null = Get-KriticalAuthorityTuple -Consumer $Value -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token }
            catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.FullyQualifiedErrorId | Should -CMatch 'ParameterArgumentValidationError'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
    }

    Context 'Item 6: invalid environments are rejected before any transport call' {

        # Item 6
        It 'item 6: environment <Name> is rejected by parameter validation with zero transport calls' -ForEach @(
            @{ Name = 'empty';         Value = '' }
            @{ Name = 'with space';    Value = 'dev test' }
            @{ Name = 'underscore';    Value = 'dev_test' }
            @{ Name = '81 characters'; Value = ('a' * 81) }
            @{ Name = 'trailing newline (regex $ matches before a final LF)'; Value = "dev`n" }
            @{ Name = 'embedded newline'; Value = "de`nv" }
        ) {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $err = $null
            try { $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment $Value -BaseUri $script:BaseUri -BearerToken $script:Token }
            catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.FullyQualifiedErrorId | Should -CMatch 'ParameterArgumentValidationError'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
    }

    Context 'Item 7: AST shape of the parameter attributes' {

        BeforeAll {
            $script:ParseTokens = $null
            $script:ParseErrors = $null
            $script:FunctionAst = [System.Management.Automation.Language.Parser]::ParseFile($script:FunctionPath, [ref]$script:ParseTokens, [ref]$script:ParseErrors)
            $script:ParamAsts = @($script:FunctionAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true))
        }

        # Item 7 (a) parse is clean and the parameter set was read at all
        It 'item 7a: the function file parses with zero errors and at least one parameter was inspected (S20)' {
            $script:ParseErrors.Count | Should -Be 0
            $script:ParamAsts.Count | Should -BeGreaterThan 0
        }

        # Item 7 (b) no ValidateSet on Consumer or Environment
        It 'item 7b: -Consumer and -Environment carry no ValidateSet attribute' {
            $targets = @($script:ParamAsts | Where-Object { $_.Name.VariablePath.UserPath -in @('Consumer', 'Environment') })
            $targets.Count | Should -Be 2
            foreach ($p in $targets) {
                $name = $p.Name.VariablePath.UserPath
                $setAttrs = @($p.Attributes | Where-Object { $_.TypeName.Name -match '^(System\.Management\.Automation\.)?ValidateSet(Attribute)?$' })
                $setAttrs.Count | Should -Be 0 -Because "-$name must validate by pattern, not ValidateSet"
            }
        }

        # Item 7 (c) ValidatePattern on each, with the exact design regex
        It 'item 7c: -Consumer has ValidatePattern ^[A-Za-z0-9._-]{1,80}$ and -Environment has ^[A-Za-z0-9-]{1,80}$' {
            $expected = @{
                Consumer    = '^[A-Za-z0-9._-]{1,80}$'
                Environment = '^[A-Za-z0-9-]{1,80}$'
            }
            $inspected = 0
            foreach ($name in $expected.Keys) {
                $p = @($script:ParamAsts | Where-Object { $_.Name.VariablePath.UserPath -eq $name })
                $p.Count | Should -Be 1
                $inspected++
                $patAttrs = @($p[0].Attributes | Where-Object { $_.TypeName.Name -match '^(System\.Management\.Automation\.)?ValidatePattern(Attribute)?$' })
                $patAttrs.Count | Should -Be 1 -Because "-$name needs exactly one ValidatePattern"
                $pattern = [string]$patAttrs[0].PositionalArguments[0].Value
                # Ruling (t6b-redproof): the design regex is the contract. The trailing '$' may be written as '\z'
                # (identical set of strings, minus the .NET quirk that '$' also matches before a final LF), because
                # a trailing-newline value must be rejected (item 5/6 behaviour cases). Nothing else may change:
                # the character class and the {1,80} bound must be verbatim. Case-insensitivity (the PowerShell
                # default) is irrelevant here as both classes allow upper and lower case.
                $strict = $expected[$name].Substring(0, $expected[$name].Length - 1) + '\z'
                $pattern | Should -BeIn @($expected[$name], $strict) -Because "-$name pattern must be the design regex (optionally with \z in place of the final `$)"
            }
            $inspected | Should -BeGreaterThan 0
        }
    }

    Context 'S20 vacuous-run guards' {

        # Item 8 (positive: a call that reaches the transport is counted)
        It 'item 8: a call that reaches the transport is counted exactly once' {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            $null = Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri $script:BaseUri -BearerToken $script:Token
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        # Item 8 (negative control: the invocation assertion must FAIL when the transport was never called)
        It 'item 8 negative control: the invocation assertion FAILS when the transport was never called' {
            Mock Invoke-RestMethod { param($Uri, $Method, $ContentType, $Headers, $Body) New-EchoMcpResponse -Body ([string]$Body) }
            { Should -Invoke Invoke-RestMethod -Times 1 -Exactly } | Should -Throw
        }
    }
}
