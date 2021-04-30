Describe 'The nomad application' {
    Context 'is installed' {
        It 'with binaries in /usr/local/bin' {
            '/usr/local/bin/nomad' | Should Exist
        }

        It 'with default configuration in /etc/nomad-conf.d/base.hcl' {
            '/etc/nomad-conf.d/base.hcl' | Should Exist
        }

        It 'with environment configuration in /etc/nomad-conf.d' {
            '/etc/nomad-conf.d/metrics.hcl' | Should Exist
            '/etc/nomad-conf.d/region.hcl' | Should Exist
            # '/etc/nomad-conf.d/secrets.hcl' | Should Exist
            '/etc/nomad-conf.d/server.hcl' | Should Exist
        }
    }

    Context 'has been daemonized' {
        $serviceConfigurationPath = '/etc/systemd/system/nomad.service'
        if (-not (Test-Path $serviceConfigurationPath))
        {
            It 'has a systemd configuration' {
                $false | Should Be $true
            }
        }

        $expectedContent = @'
[Service]
ExecStart = /usr/local/bin/nomad agent -config=/etc/nomad-conf.d
Restart = on-failure
User = nomad
[Unit]
Description = Nomad System Scheduler
Documentation = https://nomadproject.io/docs/index.html
Requires = network-online.target
After = network-online.target
[Install]
WantedBy = multi-user.target
'@
        $serviceFileContent = Get-Content $serviceConfigurationPath | Out-String
        $systemctlOutput = & systemctl status nomad
        It 'with a systemd service' {
            $serviceFileContent | Should Be ($expectedContent -replace "`r", "")

            $systemctlOutput | Should Not Be $null
            $systemctlOutput.GetType().FullName | Should Be 'System.Object[]'
            $systemctlOutput.Length | Should BeGreaterThan 3
            $systemctlOutput[0] | Should Match 'nomad.service - Nomad System Scheduler'
        }

        It 'that is enabled' {
            $systemctlOutput[1] | Should Match 'Loaded:\sloaded\s\(.*;\senabled;.*\)'

        }

        It 'and is running' {
            $systemctlOutput[2] | Should Match 'Active:\sactive\s\(running\).*'
        }
    }

    Context 'can be contacted' {
        $ifConfigResponse = & ifconfig eth0
        $line = $ifConfigResponse[1].Trim()
        # Expecting line to be:
        #     inet addr:192.168.6.46  Bcast:192.168.6.255  Mask:255.255.255.0
        $localIpAddress = $line.SubString(10, ($line.IndexOf(' ', 10) - 10))

        $response = Invoke-WebRequest -Uri "http://$($localIpAddress):4646/v1/agent/self" -UseBasicParsing
        $agentInformation = ConvertFrom-Json $response.Content
        It 'responds to HTTP calls' {
            $response.StatusCode | Should Be 200
            $agentInformation | Should Not Be $null
        }
    }

    Context 'has linked to consul' {
        $services = consul catalog services -tags
        It 'with the expected nomad services' {
            $services[0] | Should Match 'consul'
            $services[1] | Should Match 'jobs\s*http,rpc,serf'
        }
    }
}