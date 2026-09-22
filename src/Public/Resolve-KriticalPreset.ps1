function Resolve-KriticalPreset {
    <#
    .SYNOPSIS
    Resolves a preset name to its stored value, or passes the value through unchanged.

    .DESCRIPTION
    Resolve-KriticalPreset is a convenience function for command implementations to handle
    both preset names and literal values uniformly. If the provided Value matches a registered
    preset name for the given Command and Parameter, the preset's stored value is returned.
    Otherwise, the Value is returned unchanged.

    This allows functions to accept either '-Provider CpuSpike' (preset) or
    '-Provider Microsoft-Windows-Kernel-Process' (literal) interchangeably.

    .PARAMETER Command
    The command for which to resolve the preset. Mandatory.
    Example: 'Start-KritEtwCapture'

    .PARAMETER Parameter
    The parameter for which to resolve the preset. Mandatory.
    Example: 'Provider'

    .PARAMETER Value
    The value to resolve. If it matches a preset name, that preset's value is returned.
    Otherwise, this value is returned as-is. Mandatory.
    Example: 'CpuSpike' or 'Microsoft-Windows-Kernel-Process'

    .OUTPUTS
    [object] The preset's value if found, or the original Value parameter otherwise.

    .EXAMPLE
    # Resolve a preset name to its value
    $provider = Resolve-KriticalPreset -Command Start-KritEtwCapture -Parameter Provider -Value 'CpuSpike'
    # Returns: 'Microsoft-Windows-Kernel-Process' (or whatever the preset stored)

    .EXAMPLE
    # Pass through a literal value unchanged
    $provider = Resolve-KriticalPreset -Command Start-KritEtwCapture -Parameter Provider -Value 'Custom-Provider'
    # Returns: 'Custom-Provider'

    .NOTES
    Used internally by functions that accept preset names and want to expand them
    before processing the final value.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Command,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Parameter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [object]
        $Value
    )

    # Build the key for this preset lookup
    $configKey = "Kritical.Presets.$Command.$Parameter.$Value"

    # Try to retrieve the preset
    $presetConfig = Get-PSFConfig -FullName $configKey -ErrorAction SilentlyContinue

    # If found, return the preset's value; otherwise return the input value unchanged
    if ($presetConfig) {
        return $presetConfig.Value
    } else {
        return $Value
    }
}
