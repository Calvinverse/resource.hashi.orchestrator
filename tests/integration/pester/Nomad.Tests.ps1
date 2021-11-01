BeforeAll {
    $serviceConfigurationPath = '/etc/systemd/system/nomad.service'
    $localIpAddress = & ip a show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1
}

Describe 'The nomad application' {
    Context 'is installed' {
        It 'with binaries in /usr/local/bin' {
            '/usr/local/sbin/nomad' | Should -Exist
        }

        It 'with default configuration in /etc/nomad.conf.d/base.hcl' {
            '/etc/nomad.conf.d/base.hcl' | Should -Exist
        }

        It 'with environment configuration in /etc/nomad.conf.d' {
            '/etc/nomad.conf.d/metrics.hcl' | Should -Exist
            '/etc/nomad.conf.d/region.hcl' | Should -Exist
            # '/etc/nomad.conf.d/secrets.hcl' | Should Exist
            '/etc/nomad.conf.d/server.hcl' | Should -Exist
        }
    }

    Context 'has been daemonized' {
        It 'has a systemd configuration' {
            if (-not (Test-Path $serviceConfigurationPath))
            {
                $false | Should -Be $true
            }
        }

        It 'with a systemd service' {
            $expectedContent = @'
[Service]
ExecStart = /usr/local/sbin/nomad agent -config=/etc/nomad.conf.d
ExecReload = /bin/kill -HUP $MAINPID
RestartSec = 5
Restart = always
User = nomad
LimitNOFILE = infinity
LimitNPROC = infinity
KillSignal = TERM
TasksMax = infinity

[Unit]
Description = Nomad System Scheduler
Requires = network-online.target
After = network-online.target
StartLimitIntervalSec = 0

[Install]
WantedBy = multi-user.target

'@
            $serviceFileContent = Get-Content $serviceConfigurationPath | Out-String
            $systemctlOutput = & systemctl status nomad
            $serviceFileContent | Should -Be ($expectedContent -replace "`r", "")

            $systemctlOutput | Should -Not -Be $null
            $systemctlOutput.GetType().FullName | Should -Be 'System.Object[]'
            $systemctlOutput.Length | Should -BeGreaterThan 3
            $systemctlOutput[0] | Should -Match 'nomad.service - Nomad System Scheduler'
        }

        It 'that is enabled' {
            $systemctlOutput = & systemctl status nomad
            $systemctlOutput[1] | Should -Match 'Loaded:\sloaded\s\(.*;\senabled;.*\)'

        }

        It 'and is running' {
            $systemctlOutput = & systemctl status nomad
            $systemctlOutput[2] | Should -Match 'Active:\sactive\s\(running\).*'
        }
    }

    Context 'can be contacted' {
        It 'responds to HTTP calls' {
            $response = Invoke-WebRequest -Uri "http://$($localIpAddress):4646/v1/agent/self" -UseBasicParsing
            $agentInformation = ConvertFrom-Json $response.Content
            $response.StatusCode | Should -Be 200
            $agentInformation | Should -Not -Be $null
        }
    }

    Context 'has linked to consul' {
        It 'with the expected nomad services' {
            $services = consul catalog services -tags
            $services[0] | Should -Match 'consul'
            $services[1] | Should -Match 'jobs\s*http,rpc,serf'
        }
    }
}