function Get-KriticalCompleter {
    <#
    .SYNOPSIS
    Lists all registered completers, optionally filtered by command.

    .DESCRIPTION
    Get-KriticalCompleter queries the module-scoped completer registry to retrieve
    all previously registered completers (stored by Register-KriticalCompleter).
    Completers can be filtered by command name to narrow results.

    .PARAMETER Command
    Filter completers to only those registered for a specific command.
    Optional. Examples: 'Start-KritEtwCapture', 'Invoke-KritDistributedCapture'.

    .OUTPUTS
    [PSCustomObject] One object per matching completer registration with properties:
      - Command: The command this completer is registered for
      - Parameter: The parameter this completer is registered for
      - Name: The completer registration name
      - CacheSeconds: The cache duration for this completer

    .EXAMPLE
    # List all completers
    Get-KriticalCompleter

    .EXAMPLE
    # List completers for the Start-KritEtwCapture command only
    Get-KriticalCompleter -Command Start-KritEtwCapture

    .NOTES
    Queries the module-scoped _KriticalCompleterRegistry hashtable.
    If no completers have been registered, returns empty.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Command
    )

    # Get the module-scoped registry (created on first use by Register-KriticalCompleter)
    $registry = Get-Variable -Name '_KriticalCompleterRegistry' -Scope Script -ErrorAction SilentlyContinue

    if (-not $registry) {
        return
    }

    $registryTable = $registry.Value

    # Iterate through each entry in the registry
    foreach ($entry in $registryTable.GetEnumerator()) {
        $completersInfo = $entry.Value

        # $completersInfo.Command is an array of command names
        foreach ($cmd in $completersInfo.Command) {
            # Apply filter if specified
            if ($Command -and $cmd -ne $Command) {
                continue
            }

            [PSCustomObject]@{
                Command      = $cmd
                Parameter    = $completersInfo.Parameter
                Name         = $completersInfo.Name
                CacheSeconds = $completersInfo.CacheSeconds
            }
        }
    }
}
