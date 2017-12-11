#
# Cookbook Name:: dd-agent-step-by-step
# Recipe:: default
#
# Copyright (C) 2013 Datadog
#
# All rights reserved - Do Not Redistribute
#

case node['platform_family']
when 'debian'
  execute 'install debian' do
    command <<-EOF
      sudo sh -c "echo \'deb http://#{node['dd-agent-step-by-step']['repo_domain_apt']}/ #{node['dd-agent-step-by-step']['repo_branch_apt']} main\' > /etc/apt/sources.list.d/datadog.list"
      sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys c7a7da52
      sudo apt-get update
      sudo apt-get install #{node['dd-agent-step-by-step']['package_name']} -y -q
    EOF
  end

when 'rhel'
  protocol = node['platform_version'].to_i < 6 ? 'http' : 'https'

  file '/etc/yum.repos.d/datadog.repo' do
    content <<-EOF.gsub(/^ {6}/, '')
      [datadog]
      name = Datadog, Inc.
      baseurl = #{protocol}://#{node['dd-agent-step-by-step']['repo_domain_yum']}/#{node['dd-agent-step-by-step']['repo_branch_yum']}/x86_64/
      enabled=1
      gpgcheck=1
      gpgkey=#{protocol}://yum.datadoghq.com/DATADOG_RPM_KEY.public
    EOF
  end

  execute 'install rhel' do
    command <<-EOF
      sudo yum makecache
      sudo yum install -y #{node['dd-agent-step-by-step']['package_name']}
    EOF
  end
end

execute 'add config file' do
  command <<-EOF
    sudo sh -c "sed \'s/api_key:.*/api_key: #{node['dd-agent-step-by-step']['api_key']}/\' \
    /etc/datadog-agent/datadog.yaml.example > /etc/datadog-agent/datadog.yaml"
  EOF
end

service 'datadog-agent' do
  action :start
end
