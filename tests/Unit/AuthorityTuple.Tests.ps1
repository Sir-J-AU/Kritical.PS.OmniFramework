#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'Get-KriticalAuthorityTuple' {
    It 'calls only the named ES read tool and returns policy metadata, not a raw MCP wrapper' {
        $payload = @{ status='ok'; consumer='pax8'; environment='test'; rowCount=1; rows=@(@{ policy_key='client.pax8.test.client_id_env'; value_kind='env-var-name'; value_text='PAX8_CLIENT_ID'; scope='test'; description='fixture'; source_ref='fixture'; updated_utc='2026-09-10T00:00:00Z' }) } | ConvertTo-Json -Depth 8 -Compress
        $global:KritAuthorityTupleTestRequest = $null
        Mock -CommandName Invoke-RestMethod -ModuleName Kritical.PS.OmniFramework -MockWith {
            param($Uri, $Method, $ContentType, $Headers, $Body)
            $global:KritAuthorityTupleTestRequest = @{ Uri=$Uri; Method=$Method; Headers=$Headers; Body=$Body }
            [pscustomobject]@{ result = [pscustomobject]@{ content = @([pscustomobject]@{ type='text'; text=$payload }) } }
        }
        $result = Get-KriticalAuthorityTuple -Consumer pax8 -Environment test -BaseUri 'https://es.invalid/mcp' -BearerToken 'test-only-token'
        $result.status | Should -BeExactly 'ok'
        $result.rows[0].value_text | Should -BeExactly 'PAX8_CLIENT_ID'
        $global:KritAuthorityTupleTestRequest.Uri | Should -BeExactly 'https://es.invalid/mcp'
        $global:KritAuthorityTupleTestRequest.Headers.Authorization | Should -BeExactly 'Bearer test-only-token'
        $global:KritAuthorityTupleTestRequest.Body | Should -Match 'get_effective_authority_tuple'
        $global:KritAuthorityTupleTestRequest.Body | Should -Match '"consumer":"pax8"'
        Remove-Variable -Name KritAuthorityTupleTestRequest -Scope Global -ErrorAction SilentlyContinue
    }

    It 'refuses an ES not-checked answer by default instead of silently falling back to local configuration' {
        $payload = @{ status='not-checked'; reason='authority SQL connector is not configured' } | ConvertTo-Json -Compress
        Mock -CommandName Invoke-RestMethod -ModuleName Kritical.PS.OmniFramework -MockWith {
            [pscustomobject]@{ result = [pscustomobject]@{ content = @([pscustomobject]@{ type='text'; text=$payload }) } }
        }
        { Get-KriticalAuthorityTuple -Consumer d365bc -Environment prod -BaseUri 'https://es.invalid/mcp' -BearerToken 'test-only-token' } | Should -Throw '*not-checked*'
    }

    It 'rejects malformed or secret-like authority rows' {
        $payload = @{ status='ok'; consumer='pax8'; environment='dev'; rowCount=1; rows=@(@{ policy_key='client.pax8.dev.client_secret'; value_kind='string'; value_text='actual-secret-value'; scope='dev' }) } | ConvertTo-Json -Depth 8 -Compress
        Mock -CommandName Invoke-RestMethod -ModuleName Kritical.PS.OmniFramework -MockWith {
            [pscustomobject]@{ result = [pscustomobject]@{ content = @([pscustomobject]@{ type='text'; text=$payload }) } }
        }
        { Get-KriticalAuthorityTuple -Consumer pax8 -Environment dev -BaseUri 'https://es.invalid/mcp' -BearerToken 'test-only-token' } | Should -Throw '*secret-like*'
    }
}
