# frozen_string_literal: true

require 'spec_helper_acceptance'

if os[:family] == 'windows'
  docker_args = 'docker_ee => true'
  tmp_path = 'C:\\tmp\\'
  wait_for_container_seconds = 120
else
  docker_args = ''
  tmp_path = '/tmp/'
  wait_for_container_seconds = 10
end

describe 'docker stack', win_broken: true do
  before(:all) do
    retry_on_error_matching(60, 5, %r{connection failure running}) do
      install_pp = <<-MANIFEST
        class { 'docker': #{docker_args} }
        docker::swarm {'cluster_manager':
            init   => true,
            ensure => 'present',
            advertise_addr => $facts['networking']['ip'],
            listen_addr => $facts['networking']['ip'],
            require => Class['docker'],
        }
        MANIFEST
      apply_manifest(install_pp, catch_failures: true)
    end
  end

  context 'Creating stack' do
    let(:install_pp) do
      <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml'],
          ensure        => present,
        }
      MANIFEST
    end

    it 'deploys stack' do
      apply_manifest(install_pp, catch_failures: true)
      sleep wait_for_container_seconds
    end

    it 'is idempotent' do
      apply_manifest(install_pp, catch_changes: true)
    end

    it 'finds a stack' do
      run_shell('docker stack ls') do |r|
        expect(r.stdout).to match(%r{web})
      end
    end

    it 'does not find a docker container' do
      run_shell('docker ps -a -q -f "name=web_compose_test"', expect_failures: false)
    end
  end

  context 'Destroying stack' do
    let(:install) do
      <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml'],
          ensure        => present,
        }
      MANIFEST
    end

    let(:destroy) do
      <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml'],
          ensure        => absent,
        }
      MANIFEST
    end

    it 'runs successfully' do
      apply_manifest(destroy, catch_failures: true)
      sleep 10
    end

    it 'is idempotent' do
      retry_on_error_matching(10, 3, %r{Removing network web_default}) do
        apply_manifest(destroy, catch_changes: true)
      end
    end

    it 'does not find a docker stack' do
      run_shell('docker stack ls') do |r|
        expect(r.stdout).not_to match(%r{web})
      end
    end
  end

  context 'creating stack with multi compose files' do
    before(:all) do
      install_pp = <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml', '#{tmp_path}docker-stack-override.yml'],
          ensure        => present,
        }
      MANIFEST

      apply_manifest(install_pp, catch_failures: true)
    end

    it 'finds container with web_compose_test tag' do
      sleep wait_for_container_seconds
      run_shell('docker ps | grep web_compose_test', expect_failures: false)
    end
  end

  context 'Destroying project with multiple compose files' do
    let(:destroy_pp) do
      <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml', '#{tmp_path}docker-stack-override.yml'],
          ensure        => absent,
        }
      MANIFEST
    end

    before(:all) do
      install_pp = <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml', '#{tmp_path}docker-stack-override.yml'],
          ensure        => present,
        }
      MANIFEST
      apply_manifest(install_pp, catch_failures: true)

      destroy_pp = <<-MANIFEST
        docker_stack { 'web':
          compose_files => ['#{tmp_path}docker-stack.yml', '#{tmp_path}docker-stack-override.yml'],
          ensure        => absent,
        }
      MANIFEST
      retry_on_error_matching(10, 3, %r{Removing network web_default}) do
        apply_manifest(destroy_pp, catch_failures: true)
      end
      sleep 15 # Wait for containers to stop and be destroyed
    end

    it 'is idempotent' do
      retry_on_error_matching(10, 3, %r{Removing network web_default}) do
        apply_manifest(destroy_pp, catch_changes: true)
      end
    end

    it 'does not find a docker stack' do
      run_shell('docker stack ls') do |r|
        expect(r.stdout).not_to match(%r{web})
      end
    end

    it 'does not find a docker container' do
      run_shell('docker ps', expect_failures: false) do |r|
        expect(r.stdout).not_to match(%r{web_compose_test})
      end
    end
  end
end
