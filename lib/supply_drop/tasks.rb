Capistrano::Configuration.instance.load do
  namespace :puppet do
    set :puppet_source, '.'
    set :puppet_destination, '/tmp/supply_drop'
    set :puppet_command, 'puppet apply'
    set :puppet_lib, lambda { "#{puppet_destination}/modules" }
    set :puppet_parameters, lambda { puppet_verbose ? '--debug --trace puppet.pp' : 'puppet.pp' }
    set :puppet_verbose, false
    set :puppet_excludes, %w(.git .svn)
    set :puppet_stream_output, false
    set :puppet_parallel_rsync, true
    set :puppet_parallel_rsync_pool_size, 10
    set :puppet_syntax_check, false
    set :puppet_write_to_file, nil
    set :puppet_runner, nil
    set :puppet_lock_file, '/tmp/puppet.lock'

    namespace :bootstrap do
      desc "installs puppet via rubygems on an osx host"
      task :osx do
        run "#{try_sudo}gem install puppet --no-ri --no-rdoc"
      end

      desc "installs puppet via apt on an ubuntu host"
      task :ubuntu do
        run "mkdir -p #{puppet_destination}"
        run "#{try_sudo} apt-get update"
        run "#{try_sudo} apt-get install -y puppet rsync"
      end

      desc "installs puppet via apt on an debian host"
      task :debian do
        run "mkdir -p #{puppet_destination}"
        run "#{try_sudo} apt-get update"
        run "#{try_sudo} apt-get install -y puppet rsync"
      end

      desc "installs puppet via yum on a centos/red hat host"
      task :redhat do
        run "mkdir -p #{puppet_destination}"
        run "#{try_sudo} yum -y install puppet rsync"
      end

      namespace :puppetlabs do

        desc "setup the puppetlabs repo, then install via the normal method"
        task :ubuntu do
          run "echo deb http://apt.puppetlabs.com/ $(lsb_release -sc) main | #{try_sudo} tee /etc/apt/sources.list.d/puppet.list"
          run "echo deb http://apt.puppetlabs.com/ $(lsb_release -sc) dependencies | #{try_sudo} tee -a /etc/apt/sources.list.d/puppet.list"
          run "#{try_sudo} apt-key adv --keyserver keyserver.ubuntu.com --recv 4BD6EC30"
          puppet.bootstrap.ubuntu
        end

        desc "setup the puppetlabs repo, then install via the normal method"
        task :debian do
          case capture("cat /etc/debian_version")
          when /(6(\.\d){1,2}|squeeze)/
            deb_ver = "squeeze"
          when /(7(\.\d){1,2}|wheezy)/
            deb_ver = "wheezy"
          when /(8(\.\d){1,2}|jessie)/
            deb_ver = "testing"
          else
            deb_ver = false
          end

          if deb_ver
            run "echo deb http://apt.puppetlabs.com/ #{deb_ver} main | #{try_sudo} tee /etc/apt/sources.list.d/puppet.list"
            run "echo deb http://apt.puppetlabs.com/ #{deb_ver} dependencies | #{try_sudo} tee -a /etc/apt/sources.list.d/puppet.list"
            run "#{try_sudo} apt-key adv --keyserver keyserver.ubuntu.com --recv 4BD6EC30"
            puppet.bootstrap.debian
          else
            logger.info "This debian version is currently not supported by Puppetlabs."
          end
        end

        desc "setup the puppetlabs repo, then install via the normal method"
        task :redhat do
          logger.info "PuppetLabs::RedHat bootstrap is not implemented yet"
        end
      end
    end

    desc "checks the syntax of all *.pp and *.erb files"
    task :syntax_check do
      checker = SupplyDrop::SyntaxChecker.new(puppet_source)
      logger.info "Syntax Checking..."
      errors = false
      checker.validate_puppet_files.each do |file, error|
        logger.important "Puppet error: #{file}"
        logger.important error
        errors = true
      end
      checker.validate_templates.each do |file, error|
        logger.important "Template error: #{file}"
        logger.important error
        errors = true
      end
      raise "syntax errors" if errors
    end

    desc "pushes the current puppet configuration to the server"
    task :update_code, :except => { :nopuppet => true } do
      syntax_check if puppet_syntax_check
      supply_drop.rsync
    end

    desc "runs puppet with --noop flag to show changes"
    task :noop, :except => { :nopuppet => true } do
      supply_drop.lock
      transaction do
        on_rollback { supply_drop.unlock }
        supply_drop.prepare
        update_code
        supply_drop.noop
        supply_drop.unlock
      end
    end

    desc "an atomic way to noop and apply changes while maintaining a lock"
    task :noop_apply, :except => { :nopuppet => true } do
      supply_drop.lock
      transaction do
        on_rollback { supply_drop.unlock }
        supply_drop.prepare
        update_code
        supply_drop.noop
        supply_drop.apply if Capistrano::CLI.ui.agree("Apply? (yes/no) ")
        supply_drop.unlock
      end
    end

    desc "applies the current puppet config to the server"
    task :apply, :except => { :nopuppet => true } do
      supply_drop.lock
      transaction do
        on_rollback { supply_drop.unlock }
        supply_drop.prepare
        update_code
        supply_drop.apply
        supply_drop.unlock
      end
    end

    desc "clears the puppet lockfile on the server."
    task :remove_lock, :except => { :nopuppet => true} do
      logger.important "WARNING: puppet:remove_lock is depricated, please use puppet:unlock instead"
      supply_drop.unlock
    end

    desc "clears the puppet lockfile on the server."
    task :unlock, :except => { :nopuppet => true} do
      supply_drop.unlock
    end
  end
end

