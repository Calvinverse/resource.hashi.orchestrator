# frozen_string_literal: true

require 'spec_helper'

describe 'resource_hashi_orchestrator::nomad' do
  context 'creates the nomad directories' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the nomad config directory' do
      expect(chef_run).to create_directory('/etc/nomad.conf.d')
    end

    it 'creates the nomad raft directory' do
      expect(chef_run).to create_directory('/var/lib/nomad')
    end
  end

  context 'creates the nomad configuration files' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    nomad_client_config_content = <<~HCL
      client {
        enabled = false
      }
      consul {
        address = "127.0.0.1:8500"
        auto_advertise = true
        client_auto_join = true
        server_auto_join = true
        server_service_name = "jobs"
      }
      data_dir = "/var/lib/nomad"
      disable_update_check = true
      enable_syslog = true
      leave_on_interrupt = false
      leave_on_terminate = false
      log_level = "INFO"
      server {
        enabled = true
      }
    HCL
    it 'creates base.hcl in the nomad configuration directory' do
      expect(chef_run).to create_file('/etc/nomad.conf.d/base.hcl')
        .with_content(nomad_client_config_content)
    end

    nomad_metrics_content = <<~CONF
      telemetry {
          publish_allocation_metrics = true
          publish_node_metrics       = true
          statsd_address = "127.0.0.1:8125"
      }
    CONF
    it 'creates nomad metrics file in the nomad configuration directory' do
      expect(chef_run).to create_file('/etc/nomad.conf.d/metrics.hcl')
        .with_content(nomad_metrics_content)
    end
  end

  context 'configures nomad' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }
    it 'installs the nomad binaries' do
      expect(chef_run).to include_recipe('nomad::install')
    end

    it 'installs the nomad service' do
      expect(chef_run).to create_systemd_service('nomad').with(
        action: [:create],
        unit_after: %w[network-online.target],
        unit_description: 'Nomad System Scheduler',
        unit_requires: %w[network-online.target],
        service_exec_start: '/usr/local/sbin/nomad agent -config=/etc/nomad.conf.d',
        service_restart: 'always',
        service_restart_sec: 5,
        service_user: 'nomad'
      )
    end

    it 'enables the nomad service' do
      expect(chef_run).to enable_service('nomad')
    end
  end

  context 'configures the firewall for nomad' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'opens the Nomad HTTP port' do
      expect(chef_run).to create_firewall_rule('nomad-http').with(
        command: :allow,
        dest_port: 4646,
        direction: :in
      )
    end

    it 'opens the Nomad serf LAN port' do
      expect(chef_run).to create_firewall_rule('nomad-rpc').with(
        command: :allow,
        dest_port: 4647,
        direction: :in
      )
    end

    it 'opens the Nomad serf WAN port' do
      expect(chef_run).to create_firewall_rule('nomad-serf').with(
        command: :allow,
        dest_port: 4648,
        direction: :in
      )
    end
  end

  context 'adds the consul-template files for nomad' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    nomad_region_template_content = <<~CONF
      datacenter = "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
      region = "{{ keyOrDefault "config/services/orchestration/region" "unknown" }}"
    CONF
    it 'creates nomad region template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/nomad_region.ctmpl')
        .with_content(nomad_region_template_content)
    end

    consul_template_nomad_region_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/nomad_region.ctmpl"
        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/nomad.conf.d/region.hcl"
        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false
        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "systemctl restart nomad"
        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "15s"
        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false
        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0755
        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true
        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"
        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates nomad_region.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/nomad_region.hcl')
        .with_content(consul_template_nomad_region_content)
    end

    nomad_secrets_template_content = <<~CONF
      server {
      {{ with secret "secret/services/orchestration/encrypt"}}
        {{ if .Data.password }}
          encrypt = "{{ .Data.password }}"
        {{ end }}
      {{ end }}
      }
      vault {
          ca_path = "/etc/certs/ca"
          cert_file = "/var/certs/vault.crt"
          # Setting the create_from_role option causes Nomad to create tokens for tasks
          # via the provided role. This allows the role to manage what policies are
          # allowed and disallowed for use by tasks.
          create_from_role = "{{ keyOrDefault "config/services/orchestration/secrets/role" "nomad-cluster" }}"
          address = "http://{{ keyOrDefault "config/services/secrets/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "consul" }}:{{ keyOrDefault "config/services/secrets/port" "80" }}"
          enabled = {{ keyOrDefault "config/services/orchestration/secrets/enabled" "true" }}
          key_file = "/var/certs/vault.key"
          tls_skip_verify = {{ keyOrDefault "config/services/orchestration/secrets/tls/skip" "true" }}
          # Embedding the token in the configuration is discouraged. Instead users
          # should set the VAULT_TOKEN environment variable when starting the Nomad
          # agent
      {{ with secret "secret/services/orchestration/token"}}
        {{ if .Data.password }}
          token = "{{ .Data.password }}"
        {{ end }}
      {{ end }}
      }
      tls {
          http = {{ keyOrDefault "config/services/orchestration/tls/http" "false" }}
          rpc = {{ keyOrDefault "config/services/orchestration/tls/rpc" "false" }}
          ca_file = ""
          cert_file = ""
          key_file = ""
          verify_server_hostname = {{ keyOrDefault "config/services/orchestration/tls/verify" "false" }}
      }
    CONF
    it 'creates nomad secrets template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/nomad_secrets.ctmpl')
        .with_content(nomad_secrets_template_content)
    end

    consul_template_nomad_secrets_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/nomad_secrets.ctmpl"
        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/nomad.conf.d/secrets.hcl"
        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false
        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "systemctl restart nomad"
        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "15s"
        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false
        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0755
        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true
        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"
        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates nomad_secrets.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/nomad_secrets.hcl')
        .with_content(consul_template_nomad_secrets_content)
    end

    nomad_server_template_content = <<~CONF
      server {
          bootstrap_expect = {{ keyOrDefault "config/services/orchestration/bootstrap" "1" }}
      }
    CONF
    it 'creates nomad server template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/nomad_server.ctmpl')
        .with_content(nomad_server_template_content)
    end

    consul_template_nomad_server_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/nomad_server.ctmpl"
        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/nomad.conf.d/server.hcl"
        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false
        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "systemctl restart nomad"
        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "15s"
        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false
        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0755
        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true
        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"
        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates nomad_server.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/nomad_server.hcl')
        .with_content(consul_template_nomad_server_content)
    end
  end
end
