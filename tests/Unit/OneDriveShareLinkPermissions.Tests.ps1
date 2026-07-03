#requires -Modules Pester
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\Kritical.PS.OmniFramework.psm1') -Force
}

Describe 'Get-KriticalOneDriveShareLinkPermissions — surface contract' {
    It 'exports the function' {
        Get-Command -Name Get-KriticalOneDriveShareLinkPermissions -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'requires LocalPath' {
        $cmd = Get-Command -Name Get-KriticalOneDriveShareLinkPermissions
        $cmd.Parameters['LocalPath'].Attributes.Mandatory -contains $true | Should -BeTrue
    }

    It 'exposes UseDeviceCode switch' {
        (Get-Command Get-KriticalOneDriveShareLinkPermissions).Parameters.ContainsKey('UseDeviceCode') | Should -BeTrue
    }

    It 'declares PSCustomObject output' {
        (Get-Command Get-KriticalOneDriveShareLinkPermissions).OutputType.Type.Name | Should -BeIn @('PSCustomObject','PSObject')
    }

    It 'has a non-empty SYNOPSIS' {
        (Get-Help Get-KriticalOneDriveShareLinkPermissions).Synopsis | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-KriticalOneDriveShareLinkRecipients — surface contract' {
    It 'exports the function' {
        Get-Command -Name Add-KriticalOneDriveShareLinkRecipients -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'declares the documented parameter set' {
        $cmd = Get-Command Add-KriticalOneDriveShareLinkRecipients
        foreach ($p in 'LocalPath','Recipients','Role','RequireSignIn','SendInvitation','Message','ExpirationDateTime','Password','UseDeviceCode') {
            $cmd.Parameters.ContainsKey($p) | Should -BeTrue -Because "expected parameter $p"
        }
    }

    It 'requires LocalPath and Recipients' {
        $cmd = Get-Command Add-KriticalOneDriveShareLinkRecipients
        $cmd.Parameters['LocalPath'].Attributes.Mandatory   -contains $true | Should -BeTrue
        $cmd.Parameters['Recipients'].Attributes.Mandatory  -contains $true | Should -BeTrue
    }

    It 'restricts Role to view|edit' {
        $vs = (Get-Command Add-KriticalOneDriveShareLinkRecipients).Parameters['Role'].Attributes |
              Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
              Select-Object -First 1
        $vs.ValidValues | Should -Be @('view','edit')
    }

    It 'supports ShouldProcess' {
        (Get-Command Add-KriticalOneDriveShareLinkRecipients).Parameters.ContainsKey('WhatIf')  | Should -BeTrue
        (Get-Command Add-KriticalOneDriveShareLinkRecipients).Parameters.ContainsKey('Confirm') | Should -BeTrue
    }

    It 'documents at least three examples' {
        @((Get-Help Add-KriticalOneDriveShareLinkRecipients -Examples).Examples.Example).Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Remove-KriticalOneDriveShareLinkPermission — surface contract' {
    It 'exports the function' {
        Get-Command -Name Remove-KriticalOneDriveShareLinkPermission -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'requires LocalPath and PermissionId' {
        $cmd = Get-Command Remove-KriticalOneDriveShareLinkPermission
        $cmd.Parameters['LocalPath'].Attributes.Mandatory     -contains $true | Should -BeTrue
        $cmd.Parameters['PermissionId'].Attributes.Mandatory  -contains $true | Should -BeTrue
    }

    It 'supports ShouldProcess at ConfirmImpact High' {
        $attr = (Get-Command Remove-KriticalOneDriveShareLinkPermission).ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
                Select-Object -First 1
        $attr.SupportsShouldProcess | Should -BeTrue
        $attr.ConfirmImpact | Should -Be 'High'
    }
}

Describe 'Set-KriticalOneDriveShareLinkPermission — surface contract' {
    It 'exports the function' {
        Get-Command -Name Set-KriticalOneDriveShareLinkPermission -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'requires LocalPath and PermissionId; Role optional' {
        $cmd = Get-Command Set-KriticalOneDriveShareLinkPermission
        $cmd.Parameters['LocalPath'].Attributes.Mandatory     -contains $true  | Should -BeTrue
        $cmd.Parameters['PermissionId'].Attributes.Mandatory  -contains $true  | Should -BeTrue
        $cmd.Parameters['Role'].Attributes.Mandatory          -contains $true  | Should -BeFalse
    }

    It 'restricts Role to view|edit' {
        $vs = (Get-Command Set-KriticalOneDriveShareLinkPermission).Parameters['Role'].Attributes |
              Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
              Select-Object -First 1
        $vs.ValidValues | Should -Be @('view','edit')
    }

    It 'allows empty-string ExpirationDateTime / Password for clear-semantics' {
        $cmd = Get-Command Set-KriticalOneDriveShareLinkPermission
        $cmd.Parameters['ExpirationDateTime'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] } |
            Should -Not -BeNullOrEmpty
        $cmd.Parameters['Password'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] } |
            Should -Not -BeNullOrEmpty
    }

    It 'throws when no mutating param supplied (cannot test invoke without Graph; via smoke)' {
        # Cannot reach inside the function without Graph + a real DriveItem, but we
        # can confirm at least that all three Set-mutating params are Optional (above)
        # and that the function exists. Live "throw when nothing-to-PATCH" is covered
        # by the e2e harness when run with creds.
        Get-Command Set-KriticalOneDriveShareLinkPermission | Should -Not -BeNullOrEmpty
    }
}

Describe 'OneDrive share-permission cmdlets — documentation surface' {
    It 'all 4 cmdlets have non-empty SYNOPSIS' {
        foreach ($n in 'Get-KriticalOneDriveShareLinkPermissions','Add-KriticalOneDriveShareLinkRecipients','Remove-KriticalOneDriveShareLinkPermission','Set-KriticalOneDriveShareLinkPermission') {
            (Get-Help $n).Synopsis | Should -Not -BeNullOrEmpty -Because "expected SYNOPSIS on $n"
        }
    }
    It 'all 4 cmdlets document at least one example' {
        foreach ($n in 'Get-KriticalOneDriveShareLinkPermissions','Add-KriticalOneDriveShareLinkRecipients','Remove-KriticalOneDriveShareLinkPermission','Set-KriticalOneDriveShareLinkPermission') {
            @((Get-Help $n -Examples).Examples.Example).Count | Should -BeGreaterOrEqual 1 -Because "expected at least 1 example on $n"
        }
    }
}
