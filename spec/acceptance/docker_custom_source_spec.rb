# frozen_string_literal: true

require 'spec_helper_acceptance'

if os[:family] == 'windows'
  docker_args = 'docker_ee => true, docker_ee_source_location => "https://download.docker.com/components/engine/windows-server/17.06/docker-17.06.2-ee-14.zip"'
  default_image = 'winamd64/hello-seattle'
  # The default args are set because:
  # restart => 'always' - there is no service created to manage containers
  # net => 'nat' - docker uses bridged by default when running a container. When installing docker on windows the default network is NAT.
  default_docker_run_arg = "restart => 'always', net => 'nat',"
  default_run_command = 'ping 127.0.0.1 -t'
  docker_command = '"/cygdrive/c/Program Files/Docker/docker"'
else
  docker_args = ''
  default_image = 'busybox'
end
skip = false

describe 'the Puppet Docker module' do
  context 'with download location', skip: skip do
    let(:pp) do
      "class { 'docker': #{docker_args} }"
    end

    it 'runs successfully' do
      apply_manifest(pp, catch_failures: true)
    end

    it 'runs idempotently' do
      apply_manifest(pp, catch_changes: true) unless selinux == 'true'
    end

    it 'is start a docker process' do
      if os[:family] == 'windows'
        run_shell('powershell Get-Process -Name dockerd') do |r|
          expect(r.stdout).to match(%r{ProcessName})
        end
      else
        run_shell('ps aux | grep docker') do |r|
          expect(r.stdout).to match %r{dockerd -H unix:\/\/\/var\/run\/docker.sock}
        end
      end
    end

    it 'installs a working docker client' do
      run_shell("#{docker_command} ps", expect_failures: false)
    end

    it 'stops a running container and remove container' do
      pp = <<-EOS
        class { 'docker': #{docker_args} }

        docker::image { '#{default_image}':
        require => Class['docker'],
        }

        docker::run { 'container_3_6':
        image   => '#{default_image}',
        command => '#{default_run_command}',
        require => Docker::Image['#{default_image}'],
        #{default_docker_run_arg}
        }
    EOS

      pp2 = <<-EOS
        class { 'docker': #{docker_args} }

        docker::image { '#{default_image}':
        require => Class['docker'],
        }

        docker::run { 'container_3_6':
        ensure  => 'absent',
        image   => '#{default_image}',
        require => Docker::Image['#{default_image}'],
        }
    EOS

      apply_manifest(pp, catch_failures: true)
      apply_manifest(pp) unless selinux == 'true'

      # A sleep to give docker time to execute properly
      sleep 15

      run_shell("#{docker_command} ps", expect_failures: false)

      apply_manifest(pp2, catch_failures: true)
      apply_manifest(pp2, catch_changes: true) unless selinux == 'true'

      # A sleep to give docker time to execute properly
      sleep 15

      run_shell("#{docker_command} inspect container-3-6", expect_failures: true)
      if os[:family] == 'windows'
        run_shell('test -f /cygdrive/c/Users/Administrator/AppData/Local/Temp/container-3-6.service', expect_failures: true)
      else
        run_shell('test -f /etc/systemd/system/container-3-6.service', expect_failures: true)
      end
    end
  end
end
