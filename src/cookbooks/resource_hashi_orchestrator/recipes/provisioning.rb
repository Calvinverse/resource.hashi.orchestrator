# frozen_string_literal: true

#
# Cookbook Name:: resource_hashi_orchestrator
# Recipe:: provisioning
#
# Copyright 2021, P. van der Velde
#

service 'provision.service' do
  action [:enable]
end
