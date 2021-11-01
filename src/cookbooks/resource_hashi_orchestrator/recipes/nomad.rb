# frozen_string_literal: true

#
# Cookbook Name:: resource_hashi_orchestrator
# Recipe:: nomad
#
# Copyright 2021, P. van der Velde
#

nomad_user = node['nomad']['service_user']
poise_service_user nomad_user do
  group node['nomad']['service_group']
end

directory NomadCookbook::Helpers::CONFIG_ROOT.to_s do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end

directory '/var/lib/nomad' do
  owner nomad_user
  group node['nomad']['service_group']
  mode '0775'
  action :create
end

file "#{NomadCookbook::Helpers::CONFIG_ROOT}/base.hcl" do
  action :create
  content <<~HCL
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
end

#
# INSTALL NOMAD
#

# This installs nomad as follows
# - Binaries: /usr/local/bin/nomad
include_recipe 'nomad::install'

nomad_metrics_file = node['nomad']['metrics_file']
file "#{NomadCookbook::Helpers::CONFIG_ROOT}/#{nomad_metrics_file}" do
  action :create
  content <<~CONF
    telemetry {
        publish_allocation_metrics = true
        publish_node_metrics       = true
        statsd_address = "127.0.0.1:8125"
    }
  CONF
  mode '755'
end

# Install the service that will run nomad
# Command line will be: nomad agent -config="#{NomadCookbook::Helpers::CONFIG_ROOT}"
args = node['nomad']['daemon_args'].to_args

# Create the systemd service for nomad. Set it to depend on the network being up
# so that it won't start unless the network stack is initialized and has an
# IP address
systemd_service 'nomad' do
  action :create

  install do
    wanted_by %w[multi-user.target]
  end
  service do
    exec_reload '/bin/kill -HUP $MAINPID'
    exec_start "/usr/local/sbin/nomad agent #{args}"
    kill_signal 'TERM'
    limit_nofile 'infinity'
    limit_nproc 'infinity'
    restart 'always'
    restart_sec 5
    tasks_max 'infinity'
    user nomad_user
  end
  unit do
    after %w[network-online.target]
    description 'Nomad System Scheduler'
    start_limit_interval_sec 0
    requires %w[network-online.target]
  end
end

service 'nomad' do
  action :enable
end

#
# ALLOW NOMAD THROUGH THE FIREWALL
#

firewall_rule 'nomad-http' do
  command :allow
  description 'Allow Nomad HTTP traffic'
  dest_port 4646
  direction :in
end

firewall_rule 'nomad-rpc' do
  command :allow
  description 'Allow Nomad RCP traffic'
  dest_port 4647
  direction :in
end

firewall_rule 'nomad-serf' do
  command :allow
  description 'Allow Nomad Serf traffic'
  dest_port 4648
  direction :in
end

#
# CONSUL-TEMPLATE FILES
#

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

# region.hcl
nomad_region_template_file = node['nomad']['consul_template_region_file']
file "#{consul_template_template_path}/#{nomad_region_template_file}" do
  action :create
  content <<~CONF
    datacenter = "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
    region = "{{ keyOrDefault "config/services/orchestration/region" "unknown" }}"
  CONF
  mode '755'
end

nomad_region_file = node['nomad']['region_file']
file "#{consul_template_config_path}/nomad_region.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{nomad_region_template_file}"
      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{NomadCookbook::Helpers::CONFIG_ROOT}/#{nomad_region_file}"
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
  HCL
  mode '755'
end

# secrets.hcl
nomad_secrets_template_file = node['nomad']['consul_template_secrets_file']
file "#{consul_template_template_path}/#{nomad_secrets_template_file}" do
  action :create
  content <<~CONF
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
  mode '755'
end

nomad_secrets_file = node['nomad']['secrets_file']
file "#{consul_template_config_path}/nomad_secrets.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{nomad_secrets_template_file}"
      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{NomadCookbook::Helpers::CONFIG_ROOT}/#{nomad_secrets_file}"
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
  HCL
  mode '755'
end

# server.hcl
nomad_server_template_file = node['nomad']['consul_template_server_file']
file "#{consul_template_template_path}/#{nomad_server_template_file}" do
  action :create
  content <<~CONF
    server {
        bootstrap_expect = {{ keyOrDefault "config/services/orchestration/bootstrap" "1" }}
    }
  CONF
  mode '755'
end

nomad_server_file = node['nomad']['server_file']
file "#{consul_template_config_path}/nomad_server.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{nomad_server_template_file}"
      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{NomadCookbook::Helpers::CONFIG_ROOT}/#{nomad_server_file}"
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
  HCL
  mode '755'
end
