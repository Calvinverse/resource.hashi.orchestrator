# frozen_string_literal: true

#
# Cookbook Name:: resource_hashi_orchestrator
# Recipe:: default
#
# Copyright 2021, P. van der Velde
#

# Always make sure that apt is up to date
apt_update 'update' do
  action :update
end

#
# Include the local recipes
#

include_recipe 'resource_hashi_orchestrator::firewall'

include_recipe 'resource_hashi_orchestrator::meta'
include_recipe 'resource_hashi_orchestrator::nomad'
include_recipe 'resource_hashi_orchestrator::provisioning'
