function Register-KriticalCompleter {
    <#
    .SYNOPSIS
    Registers a dynamic tab-completion script block for a command parameter.

    .DESCRIPTION
    Register-KriticalCompleter wraps PSFramework's TEPP (Tab Expansion Plus Plus) registration
    and provides caching of completion values via PSFramework's own native CacheDuration
    mechanism. When a user presses TAB after the specified parameter, the script block is
    invoked (or the cached result is returned) and its results are merged with any presets
    registered for the same Command/Parameter (via Register-KriticalPreset) and offered as
    completion suggestions.

    The registration persists for the lifetime of the PowerShell session.

    .PARAMETER Command
    The name of the command (or commands) that will offer tab completion on this parameter.
    Mandatory. Examples: 'Start-KritEtwCapture', 'Get-KritHandle'.

    .PARAMETER Parameter
    The parameter name that should offer tab completion. Mandatory.
    Examples: 'Provider', 'ComputerName'.

    .PARAMETER ScriptBlock
    A script block that returns the completion values when invoked.
    The script block runs at TAB time (or is bypassed if the cache is still valid).
    Mandatory. Example: { @('Value1', 'Value2') }

    .PARAMETER Name
    A human-readable name for this completer registration. If omitted, defaults to
    "$Command.$Parameter". Optional.

    .PARAMETER CacheSeconds
    Number of seconds to cache the script block's output. If omitted, defaults to 30.
    Set to 0 to disable caching. Optional.

    .PARAMETER Force
    If specified, silently replaces an existing completer with the same Name.
    If not specified and a completer with the same Name already exists, throws an error.
    Optional.

    .OUTPUTS
    [PSCustomObject] One object per command/parameter pair with properties:
      - Command: The command name(s) passed to -Command
      - Parameter: The parameter name passed to -Parameter
      - Name: The completion registration name (default or explicit)
      - CacheSeconds: The cache duration (default or explicit)

    .EXAMPLE
    # Register a completer for ETW providers that caches for 60 seconds
    Register-KriticalCompleter -Command Start-KritEtwCapture -Parameter Provider `
        -ScriptBlock { Get-KritEtwProvider | Select-Object -ExpandProperty Name } `
        -Name 'EtwProviders' -CacheSeconds 60

    .EXAMPLE
    # Register a completer for remote hosts with the default 30-second cache
    Register-KriticalCompleter -Command Invoke-KritDistributedCapture -Parameter ComputerName `
        -ScriptBlock { Get-Content 'C:\temp\hosts.txt' }

    .NOTES
    FIX (F-P1B-001 / F-P1B-002, RECEIPT-P1-REFUTE-sonnet-20260922.md): the prior implementation
    built its own caching wrapper using the `$using:` scope modifier and/or a closure
    (`.GetNewClosure()`) over the function's local parameters, then handed that wrapper to
    Register-PSFTeppScriptblock. Register-PSFTeppArgumentCompleter internally calls
    `[PSFramework.Utility.UtilityHost]::ImportScriptBlock($scriptBlock, $true)` on the
    registered scriptblock before wiring it to PowerShell's own Register-ArgumentCompleter.
    ImportScriptBlock rebinds the scriptblock's session-state association -- proven by
    execution that this silently discards `$using:` bindings (throws
    "A Using variable cannot be retrieved...", swallowed by PSFramework's own try/catch
    around the TEPP invocation -- see teppSimpleCompleter.ps1 -- so no exception ever reaches
    the caller) AND discards `.GetNewClosure()`-captured local variables (they read back as
    $null / a null hashtable inside the rebound scriptblock, e.g. `$key` was $null, causing
    `$cache.ContainsKey($key)` to throw "Value cannot be null (Parameter 'key')", again
    swallowed). Either way PowerShell's completion pipeline then has zero results from our
    completer and falls back to its own default file-path completion -- exactly the symptom
    in P1-2/P1-3/P1-6 ("file paths returned instead").

    Two things were proven, by direct execution, to survive ImportScriptBlock:
      1. PSFramework's OWN native `-CacheDuration` parameter on Register-PSFTeppScriptblock,
         used with the RAW, unmodified caller-supplied -ScriptBlock (no wrapping at all).
         This gives exactly the P1-3 semantics (invoked once within CacheSeconds, twice
         across it) and needs no cache bookkeeping of our own.
      2. `$global:`-scoped PowerShell variables (NOT `$script:` -- also proven to break,
         even for a scriptblock authored inside a real imported module and referenced by
         `$script:`, because ImportScriptBlock/[scriptblock]::Create() re-parent the
         scriptblock away from its authoring module -- `.Module` reads back $null).

    The wrapper needed for preset-merging (contract: "ensures a completer for that parameter
    offers the preset names alongside any dynamic completer") is therefore built via
    [scriptblock]::Create() with the registration Name/Command/Parameter embedded as LITERAL
    strings (never a variable reference the rebind could break), reads the original
    scriptblock back out of a `$global:_KriticalCompleterTeppStore` hashtable (also survives
    the rebind), invokes it with `&`, and appends `Get-KriticalPreset` names for the same
    Command/Parameter. This whole wrapper is what is handed to Register-PSFTeppScriptblock
    together with -CacheDuration, so the cache covers the merged (dynamic + preset) result,
    which is what P1-3's contract intends ("scriptblock invoked once ... twice across it").

    KNOWN LIMITATION (flagged, not fixed here): when -Command is an array of more than one
    command sharing the same Name, the preset merge queries ALL commands in the array
    (Get-KriticalPreset does not know, at TEPP-invocation time in Simple mode, WHICH of the
    several bound commands is actually being completed -- PSFramework's Simple-mode template
    does not pass $commandName through). No P1 test exercises a multi-command registration,
    so this does not block GREEN; a Full-mode scriptblock (explicit
    param($commandName,$parameterName,$wordToComplete,$commandAst,$fakeBoundParameter)) would
    receive $commandName and could filter precisely, but changes how Register-PSFTeppArgumentCompleter
    resolves InnerScriptBlock/ImportScriptBlock and was not proven by execution in this lane --
    left as a candidate for the next lane, not applied speculatively.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $Command,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Parameter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [scriptblock]
        $ScriptBlock,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]
        $CacheSeconds = 30,

        [Parameter(Mandatory = $false)]
        [switch]
        $Force
    )

    # Get or create the module-scoped bookkeeping registry (read directly by Get-KriticalCompleter
    # in normal call context -- never invoked through PSFramework's TEPP/ImportScriptBlock path,
    # so $script: scope is safe here).
    if (-not (Get-Variable -Name '_KriticalCompleterRegistry' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:_KriticalCompleterRegistry = @{}
    }

    # Default the Name if not provided
    if (-not $Name) {
        $Name = "$($Command -join '.').$Parameter"
    }

    # Check for duplicates
    $registryKey = $Name
    if ($script:_KriticalCompleterRegistry.ContainsKey($registryKey) -and -not $Force) {
        throw "A completer with Name '$Name' is already registered. Use -Force to replace it."
    }

    # Determine the TEPP name (same as completer name)
    $teppName = $Name

    # $global: store for the data the TEPP-invoked wrapper needs at TAB time. Proven by
    # execution (see .NOTES) to survive PSFramework's ImportScriptBlock rebind; $script: and
    # closures/$using: do not.
    if (-not (Get-Variable -Name _KriticalCompleterTeppStore -Scope Global -ErrorAction SilentlyContinue)) {   # StrictMode-safe: never read an unset global
        $global:_KriticalCompleterTeppStore = @{}
    }
    $global:_KriticalCompleterTeppStore[$teppName] = @{
        Command     = $Command
        Parameter   = $Parameter
        ScriptBlock = $ScriptBlock
    }

    # Escape single quotes for safe embedding as PowerShell string literals in the generated
    # wrapper source below.
    $escapedTeppName = $teppName -replace "'", "''"
    $escapedParameter = $Parameter -replace "'", "''"
    $escapedCommands = ($Command | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','

    $wrapperSource = @"
`$__entry = `$global:_KriticalCompleterTeppStore['$escapedTeppName']
`$__dynamic = @()
if (`$__entry) { `$__dynamic = @(& `$__entry.ScriptBlock) }
`$__presetNames = @()
foreach (`$__cmd in @($escapedCommands)) {
    `$__presetNames += @(Get-KriticalPreset -Command `$__cmd -Parameter '$escapedParameter' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}
@(`$__dynamic) + @(`$__presetNames | Sort-Object -Unique)
"@
    $effectiveScriptBlock = [scriptblock]::Create($wrapperSource)

    $cacheDuration = if ($CacheSeconds -gt 0) { [timespan]::FromSeconds($CacheSeconds) } else { [timespan]::Zero }

    # Register with PSFramework TEPP, using its own native cache mechanism (proven to survive
    # the rebind -- see .NOTES) instead of a hand-rolled $using:/closure cache.
    try {
        Register-PSFTeppScriptblock -Name $teppName -ScriptBlock $effectiveScriptBlock -CacheDuration $cacheDuration -ErrorAction Stop
    } catch {
        throw "Failed to register TEPP scriptblock '$teppName': $_"
    }

    # Register the argument completer for each command
    foreach ($cmd in $Command) {
        try {
            Register-PSFTeppArgumentCompleter -Command $cmd -Parameter $Parameter -Name $teppName -ErrorAction Stop
        } catch {
            throw "Failed to register argument completer for command '$cmd' parameter '$Parameter': $_"
        }
    }

    # Store in the bookkeeping registry
    $script:_KriticalCompleterRegistry[$registryKey] = @{
        Command      = $Command
        Parameter    = $Parameter
        Name         = $Name
        CacheSeconds = $CacheSeconds
        TeppName     = $teppName
    }

    # Return one object per command/parameter pair
    foreach ($cmd in $Command) {
        [PSCustomObject]@{
            Command      = $cmd
            Parameter    = $Parameter
            Name         = $Name
            CacheSeconds = $CacheSeconds
        }
    }
}
