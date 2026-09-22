function Register-KriticalPreset {
    <#
    .SYNOPSIS
    Registers a named answer set (preset) for a command parameter.

    .DESCRIPTION
    Register-KriticalPreset stores a named value under PSFramework configuration, accessible
    to both the interactive user and programmatically via Resolve-KriticalPreset and
    Get-KriticalPreset. Presets appear in tab completion listings for their parameter,
    allowing users to select common answer sets by name (e.g., '-Provider CpuSpike' instead
    of typing the full provider name).

    The preset is persisted in PSFramework config under the key:
    Kritical.Presets.<Command>.<Parameter>.<Name>

    .PARAMETER Name
    The preset name, as users will type it at the TAB prompt.
    Mandatory. Examples: 'CpuSpike', 'NetworkLatency', 'HighMemory'.

    .PARAMETER Command
    The command that accepts this preset. Mandatory.
    Example: 'Start-KritEtwCapture'

    .PARAMETER Parameter
    The parameter name that accepts this preset. Mandatory.
    Example: 'Provider'

    .PARAMETER Value
    The value to store under this preset name. Mandatory. Can be any PowerShell type
    (string, object, array, etc.).
    Example: 'Microsoft-Windows-Kernel-Process'

    .PARAMETER Description
    A human-readable description of what this preset does or represents.
    Optional. Stored in PSFramework config for reference.
    Example: 'ETW providers for CPU spike analysis'

    .PARAMETER Force
    If specified, silently replaces an existing preset with the same Name.
    If not specified and a preset with the same Name already exists, throws an error.
    Optional.

    .OUTPUTS
    None. Presets are stored in PSFramework config but do not return objects.

    .EXAMPLE
    # Register a preset for CPU spike analysis
    Register-KriticalPreset -Name 'CpuSpike' -Command Start-KritEtwCapture `
        -Parameter Provider -Value 'Microsoft-Windows-Kernel-Process' `
        -Description 'ETW provider for CPU spike analysis'

    .EXAMPLE
    # Register a preset for network latency (object array)
    Register-KriticalPreset -Name 'NetworkLatency' -Command Start-KritEtwCapture `
        -Parameter Provider -Value @('Microsoft-Windows-TCPIP', 'Microsoft-Windows-DNS-Client') `
        -Description 'Multiple providers for network latency analysis' -Force

    .NOTES
    Uses PSFramework's Set-PSFConfig to persist presets (in-memory, current session only --
    see the KNOWN GAP below). Warns if the Command does not resolve to an existing command
    (the command may load later).

    FIX (F-P1B-003, RECEIPT-P1-REFUTE-sonnet-20260922.md): the prior implementation always
    passed `-Initialize` to Set-PSFConfig, including on a -Force replace. Proven by direct
    execution: `-Initialize` on Set-PSFConfig is a "set the default only if nothing has set
    this value yet" flag -- calling `Set-PSFConfig -FullName <key> -Value X -Initialize` a
    second time with a different value is a silent no-op; the first-registered value is kept.
    That is exactly why P1-7b ("duplicate Name with -Force replaces") failed: the Force branch
    still called Set-PSFConfig with -Initialize, so 'ReplacedValue' never took.  Fix: pass
    -Initialize only on first registration (when no existing config entry was found); when
    replacing an existing entry (the -Force path), call Set-PSFConfig WITHOUT -Initialize, so
    the value is actually assigned.

    KNOWN GAP (flagged, not fixed here -- see RECEIPT-P1-REFUTE-sonnet-20260922.md F-P1B-00X):
    Set-PSFConfig alone only sets the value in the CURRENT process's in-memory configuration.
    Proven by execution: a value set this way in one pwsh process is invisible to a second,
    freshly started pwsh process that re-imports the module. PSFramework's actual persistence
    command is the separate `Register-PSFConfig` (writes to registry/AppData). The P1-4 test
    is titled "...retrieved after fresh Import-Module" but never actually starts a fresh
    process or re-imports in a new session -- it re-reads the same in-memory config in the
    same process, so it passes today regardless of this gap. True cross-session persistence
    (contract test list item 4, read literally) would need an additional
    `Register-PSFConfig -FullName $configKey -Scope UserDefault` call here, which was
    deliberately NOT added in this candidate fix: it would write to the operator's REAL
    PSFramework user config store (registry/AppData), not a sandboxed test location, and nothing
    in the current AfterAll cleanup un-registers persisted (as opposed to in-memory) settings --
    adding it would leak real config outside test scope. Left for Opus/operator to decide
    scope + a matching persisted-cleanup path before it is added.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Command,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Parameter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [object]
        $Value,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Description,

        [Parameter(Mandatory = $false)]
        [switch]
        $Force
    )

    # Check if the command exists; warn if not
    if (-not (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
        Write-Warning "Command '$Command' does not exist or is not yet loaded. Preset '$Name' will still be registered."
    }

    # Build the PSFramework config key
    $configKey = "Kritical.Presets.$Command.$Parameter.$Name"

    # Check for duplicates
    $existing = Get-PSFConfig -FullName $configKey -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        throw "A preset named '$Name' for command '$Command' parameter '$Parameter' is already registered. Use -Force to replace it."
    }

    # Store the preset in PSFramework config.
    # F-P1B-003: -Initialize only takes effect the FIRST time a key is set (it is a
    # set-the-default-if-unset flag, proven by execution) -- pass it only when there is no
    # existing entry. On a -Force replace of an existing entry, omit -Initialize so the new
    # Value actually takes.
    try {
        if ($existing) {
            Set-PSFConfig -FullName $configKey -Value $Value -PassThru -ErrorAction Stop | Out-Null
        } else {
            Set-PSFConfig -FullName $configKey -Value $Value -Initialize -PassThru -ErrorAction Stop | Out-Null
        }
    } catch {
        throw "Failed to register preset '$Name': $_"
    }

    # Optionally store the description in a separate config key (same -Initialize-only-on-first-set rule)
    if ($Description) {
        $descKey = "$configKey.Description"
        $existingDesc = Get-PSFConfig -FullName $descKey -ErrorAction SilentlyContinue
        try {
            if ($existingDesc) {
                Set-PSFConfig -FullName $descKey -Value $Description -PassThru -ErrorAction Stop | Out-Null
            } else {
                Set-PSFConfig -FullName $descKey -Value $Description -Initialize -PassThru -ErrorAction Stop | Out-Null
            }
        } catch {
            # Ignore description storage failures
        }
    }

    # Preset names are picked up dynamically at TAB time by Register-KriticalCompleter's
    # wrapper (it calls Get-KriticalPreset -Command -Parameter live on every invocation, or
    # cache expiry) -- nothing to push here.
}
