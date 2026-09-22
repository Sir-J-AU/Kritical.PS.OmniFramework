#requires -Modules Pester
# Author: Claude Sonnet 5 - Kritical Pty Ltd (v2 fixes over Completion.Tests.ps1, see RECEIPT-P1-RED-PROOF-sonnet-20260922.md)
#
# v3 fix over v2 (F-P1B-004, RECEIPT-P1-REFUTE-sonnet-20260922.md, internals-p1-refute-sonnet-20260922):
#   AfterAll called `Unregister-PSFConfig -FullName $_.FullName -Confirm:$false -ErrorAction SilentlyContinue`.
#   PSFramework 1.14.450's Unregister-PSFConfig has `[CmdletBinding(DefaultParameterSetName = 'Pipeline', ...)]`
#   with NO `SupportsShouldProcess = $true` -- proven by reading the shipped .ps1 (and by execution: the call
#   throws `ParameterBindingException: A parameter cannot be found that matches parameter name 'Confirm'`,
#   which is NOT swallowed by -ErrorAction SilentlyContinue because parameter binding fails before the
#   command's own ErrorAction applies, and this crashes the whole AfterAll block, which Pester reports as a
#   container-level failure even though all 22 individual It-blocks otherwise pass/fail on their own merits).
#   Fix: drop `-Confirm:$false` (two call sites, both here in AfterAll). No other change in this file.
#   FOLLOW-UP (F-P1B-006, RECEIPT-P1-REFUTE-sonnet-20260922.md): Unregister-PSFConfig's own help states
#   "This command has no effect on configuration settings currently in memory" -- since Register-KriticalPreset
#   only ever calls Set-PSFConfig (never Register-PSFConfig), nothing this AfterAll targeted was ever actually
#   persisted, so dropping -Confirm alone made the call stop THROWING but it remained a documented no-op --
#   proven by execution: running this file's Invoke-Pester twice in the SAME process (the estate's own
#   "test the second run" rule) left 4 tests RED on the second pass, all "preset ... already registered" /
#   a stale warning-state collision, because the first run's in-memory presets were never actually removed.
#   Real fix (applied below): PSFramework exposes no *public* command that deletes an in-memory-only config
#   entry (Unregister-PSFConfig only touches persisted registry/AppData values; Reset-PSFConfig reverts a
#   value to its -Initialize default without removing the entry) -- but
#   `[PSFramework.Configuration.ConfigurationHost]::Configurations` (a public static
#   ConcurrentDictionary<string,Config>) DOES support `.Remove(<FullName>)`, and this was proven by execution
#   to actually delete the entry (Get-PSFConfig returns nothing for it afterwards, case-insensitively).
# Completion layer P1 tests: Register-KriticalCompleter, Register-KriticalPreset,
# Get-KriticalPreset, Resolve-KriticalPreset, Get-KriticalCompleter
#
# Fixes applied over the v1 file (each references its F-P1-nnn finding in the receipt):
#   F-P1-001 P1-8a: the trailing `  # Empty return` comment after a line-continuation backtick
#            broke the intended single statement into two, orphaning `-Name`/`-Force` as a
#            bogus second statement that always throws CommandNotFoundException. Comment moved
#            off the continuation line.
#   F-P1-002 cursorColumn 26 against a 25-character input string ('Start-KritDemo -Provider ')
#            is out of range and TabExpansion2 always throws, for ANY implementation, correct
#            or not. Every call now uses $script:DemoInputScript.Length (computed once).
#   F-P1-003/004 $script:TestConfigPrefix was 'Kritical.Presets.KritDemo' but the contract's
#            key shape is 'Kritical.Presets.<Command>.<Parameter>.<Name>' with Command bound to
#            the literal value passed to -Command, i.e. 'Start-KritDemo' -- not 'KritDemo'. P1-4
#            queried a key that a correct implementation never writes (proven by golden-reference
#            execution in the receipt) and the AfterAll cleanup pattern matched nothing, leaking
#            every preset created by the whole file into real PSFramework config under
#            'Kritical.Presets.Start-KritDemo.*' for the rest of the process. Prefix corrected to
#            match the literal Command value actually used throughout this file.
#   F-P1-009 P1-8b only asserted `Should -Not -Throw`; a no-op implementation that neither warns
#            nor throws would also pass. Now captures -WarningVariable and asserts it is non-empty.
#            -WarningVariable sets the variable in the CALLER's own scope: passing it to a call
#            wrapped in `{ ... } | Should -Not -Throw` sets it inside that scriptblock's own child
#            scope, invisible to the It block afterwards (proven by execution in the receipt --
#            the naive version always captured $null). Rewritten with try/catch so the call and
#            its -WarningVariable are direct statements in the It block's own scope.
#   F-P1-007/008 (WEAK, strengthened) the Get-KriticalPreset / Get-KriticalCompleter "filters by"
#            tests only asserted non-null, so an implementation that ignores the filter and
#            returns everything would also pass. Added a decoy preset/completer under an unrelated
#            command and asserted it is EXCLUDED by the filtered call.
#   F-P1-010 P1-8a asserted `$expansion.CompletionMatches | Should -BeNullOrEmpty` for an empty
#            TEPP scriptblock. Proven by execution (receipt) that when a registered TEPP
#            scriptblock returns zero values, PowerShell's own completion pipeline falls back to
#            default file-path completion (19 matches from cwd in the reproduction) -- so this
#            assertion could NEVER pass, for any implementation, correct or defective. Fixed to
#            check that none of the returned CompletionMatches carry ResultType 'ParameterValue'
#            (proven: our own TEPP-sourced values always report ParameterValue; file-fallback
#            matches report ProviderItem and never ParameterValue) -- this proves OUR completer
#            contributed nothing, independent of whatever the shell's fallback adds.

BeforeAll {
    # Import the module by manifest path as specified in the contract
    Import-Module 'C:\NoOneDrive\Github\Kritical.PS.OmniFramework\src\Kritical.PS.OmniFramework.psd1' -Force -DisableNameChecking -ErrorAction SilentlyContinue
    # Fallback to psm1 if manifest fails due to missing dependencies
    if (-not (Get-Module Kritical.PS.OmniFramework)) {
        Import-Module 'C:\NoOneDrive\Github\Kritical.PS.OmniFramework\src\Kritical.PS.OmniFramework.psm1' -Force
    }

    # Test-scoped PSFramework config key prefix to avoid touching real user config.
    # F-P1-003/004: this MUST equal 'Kritical.Presets.<literal -Command value used below>' --
    # every call in this file passes -Command Start-KritDemo, so the prefix is
    # 'Kritical.Presets.Start-KritDemo', not 'Kritical.Presets.KritDemo'.
    $script:TestConfigPrefix = 'Kritical.Presets.Start-KritDemo'
    $script:CacheTestCounter = @{ Invocations = 0 }

    # Demo function for completion testing (tab-completable -Provider parameter)
    function Start-KritDemo {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $false)]
            [string]
            $Provider
        )
        Write-Output "Provider: $Provider"
    }

    # Decoy function for a second, unrelated command -- used to prove filters actually
    # exclude non-matching entries (F-P1-007/008) rather than returning everything.
    function Start-KritDecoy {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $false)]
            [string]
            $Provider
        )
        Write-Output "Decoy: $Provider"
    }

    # F-P1B-005 (RECEIPT-P1-REFUTE-sonnet-20260922.md): a command/parameter pair that NO test
    # in this file ever registers a preset against. A contract-correct Register-KriticalCompleter
    # merges preset names into EVERY completer registered for a given Command+Parameter (that is
    # the whole point of P1-6), so P1-8a's "this completer contributes nothing" proof needs a
    # pair with zero presets ever attached to it, or it would see OTHER tests' presets
    # (CpuSpike, ForceTest, Preset1, Preset2, TestPreset, PresetInCompletion...) leak in as
    # ParameterValue completions and falsely look like the empty completer "contributed"
    # something. Start-KritDecoy is NOT reused here because the Get-KriticalPreset Describe
    # block's BeforeEach registers 'DecoyPreset' against Start-KritDecoy/Provider on every run.
    function Start-KritEmptyDecoy {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $false)]
            [string]
            $Provider
        )
        Write-Output "EmptyDecoy: $Provider"
    }

    # F-P1-002: the input script and its true length, computed once, used by every
    # TabExpansion2 call in this file instead of a hardcoded (and wrong) cursor column.
    $script:DemoInputScript = 'Start-KritDemo -Provider '
    $script:DemoCursorColumn = $script:DemoInputScript.Length

    # F-P1B-005: input/cursor for the preset-free Start-KritEmptyDecoy command (P1-8a only).
    $script:EmptyDecoyInputScript = 'Start-KritEmptyDecoy -Provider '
    $script:EmptyDecoyCursorColumn = $script:EmptyDecoyInputScript.Length
}

AfterAll {
    # F-P1B-006: Unregister-PSFConfig only affects PERSISTED settings and is a documented no-op
    # against these in-memory-only presets (Register-KriticalPreset never calls Register-PSFConfig).
    # Remove the entries directly from PSFramework's public static config dictionary so a second
    # Invoke-Pester in the same process starts clean (proven by execution -- see header note).
    # Cleaned broadly under the whole 'Kritical.Presets.*' namespace (not just $script:TestConfigPrefix)
    # because P1-8b deliberately registers a preset under a NON-Start-KritDemo command
    # ('Non-Existent-Command-XYZ') to prove the warn-not-throw path -- that key falls outside every
    # per-command prefix above and was still leaking pre-this-fix. This whole namespace is exclusively
    # owned by this test file's presets (contract's key shape is 'Kritical.Presets.<Command>...'), so a
    # blanket sweep here does not touch any real, non-test PSFramework config.
    Get-PSFConfig -FullName 'Kritical.Presets.*' -ErrorAction SilentlyContinue | ForEach-Object {
        $null = [PSFramework.Configuration.ConfigurationHost]::Configurations.Remove($_.FullName)
    }

    # Remove demo functions
    Remove-Item -Path Function:\Start-KritDemo -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\Start-KritDecoy -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\Start-KritEmptyDecoy -ErrorAction SilentlyContinue
}

# Test that the five required functions exist (expected to fail until they are implemented)
Describe 'Register-KriticalCompleter' {
    It 'exists as a command' {
        Get-Command -Name Register-KriticalCompleter -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'P1-1: registration returns one object per command/parameter pair' {
        Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock { @('ETW-Provider-A', 'ETW-Provider-B') } `
            -Name 'DemoProviders' -CacheSeconds 30 |
            Should -Not -BeNullOrEmpty

        $result = Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock { @('ETW-Provider-A', 'ETW-Provider-B') } `
            -Name 'DemoProviders' -CacheSeconds 30 -Force

        $result | Should -HaveCount 1
        $result.Command | Should -Be 'Start-KritDemo'
        $result.Parameter | Should -Be 'Provider'
        $result.Name | Should -Match 'DemoProviders'
        $result.CacheSeconds | Should -Be 30
    }

    It 'P1-2: TabExpansion2 yields the scriptblock values' {
        Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock { @('Microsoft-Windows-Kernel-Process', 'Microsoft-Windows-DNS-Client') } `
            -Name 'SystemProviders' -Force

        $expansion = TabExpansion2 -inputScript $script:DemoInputScript -cursorColumn $script:DemoCursorColumn
        $expansion.CompletionMatches.CompletionText | Should -Contain 'Microsoft-Windows-Kernel-Process'
        $expansion.CompletionMatches.CompletionText | Should -Contain 'Microsoft-Windows-DNS-Client'
    }

    It 'P1-3: cache: scriptblock invoked once within CacheSeconds, twice across it' {
        $script:CacheTestCounter.Invocations = 0
        $cacheScriptBlock = {
            $script:CacheTestCounter.Invocations += 1
            @('CachedValue1', 'CachedValue2')
        }

        Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock $cacheScriptBlock -Name 'CacheTest' -CacheSeconds 1 -Force

        # First call should invoke the scriptblock
        $null = TabExpansion2 -inputScript $script:DemoInputScript -cursorColumn $script:DemoCursorColumn
        $firstCount = $script:CacheTestCounter.Invocations
        $firstCount | Should -Be 1

        # Second call within CacheSeconds should use cache
        $null = TabExpansion2 -inputScript $script:DemoInputScript -cursorColumn $script:DemoCursorColumn
        $secondCount = $script:CacheTestCounter.Invocations
        $secondCount | Should -Be 1  # Still 1, cache hit

        # Wait for cache to expire
        Start-Sleep -Seconds 1.1

        # Third call after CacheSeconds should invoke scriptblock again
        $null = TabExpansion2 -inputScript $script:DemoInputScript -cursorColumn $script:DemoCursorColumn
        $thirdCount = $script:CacheTestCounter.Invocations
        $thirdCount | Should -Be 2  # Now 2, cache expired
    }
}

Describe 'Register-KriticalPreset' {
    It 'exists as a command' {
        Get-Command -Name Register-KriticalPreset -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'P1-4: preset persisted in PSFramework config and retrieved after fresh Import-Module' {
        Register-KriticalPreset -Name 'CpuSpike' -Command Start-KritDemo -Parameter Provider `
            -Value 'Microsoft-Windows-Kernel-Process' -Description 'CPU spike ETW providers'

        # Verify it was persisted under the key shape the contract actually specifies:
        # Kritical.Presets.<Command>.<Parameter>.<Name>  ==  Kritical.Presets.Start-KritDemo.Provider.CpuSpike
        $preset = Get-PSFConfig -FullName "$script:TestConfigPrefix.Provider.CpuSpike" -ErrorAction SilentlyContinue
        $preset | Should -Not -BeNullOrEmpty
        $preset.Value | Should -Be 'Microsoft-Windows-Kernel-Process'
    }

    It 'P1-7a: duplicate Name without -Force throws' {
        Register-KriticalPreset -Name 'DupTest' -Command Start-KritDemo -Parameter Provider `
            -Value 'Provider1'

        { Register-KriticalPreset -Name 'DupTest' -Command Start-KritDemo -Parameter Provider -Value 'Provider2' } |
            Should -Throw
    }

    It 'P1-7b: duplicate Name with -Force replaces' {
        Register-KriticalPreset -Name 'ForceTest' -Command Start-KritDemo -Parameter Provider `
            -Value 'OriginalValue'

        Register-KriticalPreset -Name 'ForceTest' -Command Start-KritDemo -Parameter Provider `
            -Value 'ReplacedValue' -Force

        $result = Get-KriticalPreset -Name 'ForceTest'
        $result.Value | Should -Be 'ReplacedValue'
    }
}

Describe 'Get-KriticalPreset' {
    BeforeEach {
        # Register test presets, plus a decoy under an unrelated command/parameter so the
        # -Command / -Parameter filters below can prove exclusion, not just non-emptiness.
        Register-KriticalPreset -Name 'Preset1' -Command Start-KritDemo -Parameter Provider `
            -Value 'Value1' -Description 'Test preset 1' -Force -ErrorAction SilentlyContinue
        Register-KriticalPreset -Name 'Preset2' -Command Start-KritDemo -Parameter Provider `
            -Value 'Value2' -Description 'Test preset 2' -Force -ErrorAction SilentlyContinue
        Register-KriticalPreset -Name 'DecoyPreset' -Command Start-KritDecoy -Parameter Provider `
            -Value 'DecoyValue' -Description 'Decoy preset for a different command' -Force -ErrorAction SilentlyContinue
    }

    It 'exists as a command' {
        Get-Command -Name Get-KriticalPreset -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'lists all presets when called without parameters' {
        $presets = Get-KriticalPreset
        $presets | Should -Not -BeNullOrEmpty
        $presets.Name | Should -Contain 'DecoyPreset'
    }

    It 'filters by -Name' {
        $preset = Get-KriticalPreset -Name 'Preset1'
        $preset.Name | Should -Be 'Preset1'
        $preset.Value | Should -Be 'Value1'
    }

    It 'filters by -Command' {
        $presets = Get-KriticalPreset -Command Start-KritDemo
        $presets | Should -Not -BeNullOrEmpty
        $presets.Name | Should -Contain 'Preset1'
        # F-P1-007: a filter that ignores -Command and returns everything must fail this.
        $presets.Name | Should -Not -Contain 'DecoyPreset'
    }

    It 'filters by -Parameter' {
        $presets = Get-KriticalPreset -Parameter Provider
        $presets | Should -Not -BeNullOrEmpty
    }
}

Describe 'Resolve-KriticalPreset' {
    BeforeEach {
        Register-KriticalPreset -Name 'TestPreset' -Command Start-KritDemo -Parameter Provider `
            -Value 'ResolvedProviderValue' -Force -ErrorAction SilentlyContinue
    }

    It 'exists as a command' {
        Get-Command -Name Resolve-KriticalPreset -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'P1-5a: expands a preset name to its stored Value' {
        $result = Resolve-KriticalPreset -Command Start-KritDemo -Parameter Provider -Value TestPreset
        $result | Should -Be 'ResolvedProviderValue'
    }

    It 'P1-5b: passes non-preset values through untouched' {
        $result = Resolve-KriticalPreset -Command Start-KritDemo -Parameter Provider -Value 'LiteralValue'
        $result | Should -Be 'LiteralValue'
    }
}

Describe 'Get-KriticalCompleter' {
    BeforeEach {
        Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock { @('Completer1', 'Completer2') } `
            -Name 'TestCompleter' -Force -ErrorAction SilentlyContinue
        Register-KriticalCompleter -Command Start-KritDecoy -Parameter Provider `
            -ScriptBlock { @('DecoyCompleter1') } `
            -Name 'DecoyCompleter' -Force -ErrorAction SilentlyContinue
    }

    It 'exists as a command' {
        Get-Command -Name Get-KriticalCompleter -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'lists all completers when called without parameters' {
        $completers = Get-KriticalCompleter
        $completers | Should -Not -BeNullOrEmpty
        $completers.Command | Should -Contain 'Start-KritDecoy'
    }

    It 'filters by -Command' {
        $completers = Get-KriticalCompleter -Command Start-KritDemo
        $completers | Should -Not -BeNullOrEmpty
        $completers.Command | Should -Contain 'Start-KritDemo'
        # F-P1-008: a filter that ignores -Command and returns everything must fail this.
        $completers.Command | Should -Not -Contain 'Start-KritDecoy'
    }
}

Describe 'P1-6: preset names appear in completion alongside dynamic values' {
    BeforeEach {
        Register-KriticalCompleter -Command Start-KritDemo -Parameter Provider `
            -ScriptBlock { @('DynamicProvider1', 'DynamicProvider2') } `
            -Name 'DynamicProviders' -Force -ErrorAction SilentlyContinue

        Register-KriticalPreset -Name 'PresetInCompletion' -Command Start-KritDemo -Parameter Provider `
            -Value 'PresetProviderValue' -Force -ErrorAction SilentlyContinue
    }

    It 'preset names and dynamic values both appear in completion' {
        $expansion = TabExpansion2 -inputScript $script:DemoInputScript -cursorColumn $script:DemoCursorColumn
        $matches = $expansion.CompletionMatches.CompletionText

        $matches | Should -Contain 'DynamicProvider1'
        $matches | Should -Contain 'DynamicProvider2'
        $matches | Should -Contain 'PresetInCompletion'
    }
}

Describe 'P1-8: planted defects must make tests RED' {
    It 'P1-8a: completer that returns nothing' {
        # F-P1-001: comment moved off the continuation line -- a backtick line-continuation
        # must be the LAST character on its physical line or it silently stops continuing.
        # F-P1B-005: registered against Start-KritEmptyDecoy, NOT Start-KritDemo -- every other
        # test in this file registers presets against Start-KritDemo/Provider, and a
        # contract-correct completer merges ALL presets for its Command+Parameter regardless of
        # which completer Name asked for it, so asserting "zero ParameterValue matches" against
        # Start-KritDemo would fail even for a correct implementation once other tests' presets
        # have accumulated in the shared session. Start-KritEmptyDecoy has zero presets ever
        # registered against it anywhere in this file.
        Register-KriticalCompleter -Command Start-KritEmptyDecoy -Parameter Provider `
            -ScriptBlock { @() } `
            -Name 'EmptyCompleter' -Force -ErrorAction SilentlyContinue

        $expansion = TabExpansion2 -inputScript $script:EmptyDecoyInputScript -cursorColumn $script:EmptyDecoyCursorColumn
        # F-P1-010: cannot assert the whole match set is empty -- PowerShell falls back to file
        # completion when the registered TEPP scriptblock returns nothing. Assert instead that
        # none of the matches were contributed by a ParameterValue-type completer (ours).
        $parameterValueMatches = @($expansion.CompletionMatches | Where-Object ResultType -eq 'ParameterValue')
        $parameterValueMatches | Should -BeNullOrEmpty
    }

    It 'P1-8b: preset with non-existent Command warns' {
        # F-P1-009: capture the warning stream and assert it actually fired, not just that
        # no exception was thrown -- a silent no-op must fail this. The call is a direct
        # statement (not wrapped in a nested scriptblock) so -WarningVariable lands in this
        # It block's own scope rather than a throwaway child scope.
        $warnings = $null
        $threw = $false
        try {
            Register-KriticalPreset -Name 'BadCommandPreset' -Command 'Non-Existent-Command-XYZ' -Parameter Provider `
                -Value 'Value' -WarningVariable warnings -WarningAction SilentlyContinue
        } catch {
            $threw = $true
        }
        $threw | Should -BeFalse  # Should warn, not throw
        $warnings | Should -Not -BeNullOrEmpty
    }
}
