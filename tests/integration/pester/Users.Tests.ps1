BeforeAll {
    $content = Get-Content '/etc/passwd'

    $users = @()
    foreach ($line in $content)
    {
        $sections = $line.Split(':')
        $userId = [int]($sections[3])
        if (($userId -ge 1000) -and ($userId -lt 65534))
        {
            $users += $sections[0]
        }
    }
}

Describe 'The users list' {
    Context 'on the machine' {
        It 'should contain a default user' {
            $users.Length | Should -Be 1
            if ([Environment]::GetEnvironmentVariable('Hypervisor') -eq 'azure' )
            {
                # On Azure packer will set its own user name
                $users[0] | Should -Be 'packer'
            }
            else
            {
                $users[0] | Should -Be '${LocalAdministratorName}'
            }
        }
    }
}