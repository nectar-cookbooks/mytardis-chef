#
# Cookbook Name:: mytardis
# Recipe:: default
#
# Copyright (c) 2012, 2014, The University of Queensland
# Copyright (c) 2012, 2013, The MyTardis Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the The University of Queensland nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE UNIVERSITY OF QUEENSLAND BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

if platform?("ubuntu","debian")
  include_recipe "apt"
end
include_recipe "git"
include_recipe "mytardis::build-essential"
include_recipe "mytardis::deps"
include_recipe "mytardis::nginx"
include_recipe "mytardis::postgresql"
include_recipe "mytardis::logwatch"
include_recipe "mytardis::logrotate"

production = node["mytardis"]["production"]
if node["mytardis"]["allow_migrations"] != nil then
  allow_migrations = node["mytardis"]["allow_migrations"]
else
  allow_migrations = !production
end
if node["mytardis"]["backups"] != nil then
  backups = node["mytardis"]["backups"]
else
  backups = production
end

ohai "reload_passwd" do
  action :nothing
  plugin "passwd"
end

user "mytardis" do
  action :create
  comment "MyTardis Large Data Repository"
  system true
  supports :manage_home => true
  notifies :reload, resources(:ohai => "reload_passwd"), :immediately
end

app_dirs = [
  "/opt/mytardis",
  "/opt/mytardis/shared",
  "/opt/mytardis/shared/apps",
  "/var/lib/mytardis",
  "/var/log/mytardis"
]

app_links = {
  "/opt/mytardis/shared/data" => "/var/lib/mytardis",
  "/opt/mytardis/shared/log" => "/var/log/mytardis"
}

app_dirs.each do |dir|
  directory dir do
    owner "mytardis"
    group "mytardis"
  end
end

app_links.each do |k, v|
  link k do
    to v
    owner "mytardis"
    group "mytardis"
  end
end

cookbook_file "/opt/mytardis/shared/buildout.cfg" do
  action :create
  source "buildout.cfg"
  owner "mytardis"
  group "mytardis"
end

template "/opt/mytardis/shared/settings.py" do
  action :create_if_missing
  source "settings-py.erb"
  owner "mytardis"
  group "mytardis"
end

##
## FIXME ... hardwiring an old version of foreman means won't be able to
## make use of foreman systemd support (for fedora) ... when it eventually
## gets released.
##
bash "install foreman" do
  code <<-EOH
  # Version 0.48 removes 'log_root' variable
  gem install foreman -v 0.47.0
  EOH
  #this fails on NeCTAR Ubuntu Lucid..
  # only_if do
  #   output = `gem list --local | grep foreman`
  #   output.length == 0
  # end
end

# Get the apps first, so they get symlinked correctly
app_symlinks = {}

deploy_revision "mytardis" do
  action :deploy
  deploy_to "/opt/mytardis"
  repository node['mytardis']['repo']
  branch node['mytardis']['branch']
  user "mytardis"
  group "mytardis"
  migrate true
  symlink_before_migrate({})
  purge_before_symlink([])
  create_dirs_before_symlink([])
  symlinks({})
  before_migrate do
    current_release = release_path

    # Create symlinks by hand.  (Pre-migration symlink creation is too late.)
    app_symlinks.merge({
                         "data" => "var",
                         "log" => "log",
                         "buildout.cfg" => "buildout-prod.cfg",
                         "settings.py" => "tardis/settings.py"}).each do |s, d|
      src = "#{new_resource.shared_path}/#{s}"
      dest = "#{release_path}/#{d}"
      begin
        FileUtils.ln_sf(src, dest)
      rescue => e
        raise Chef::Exceptions::FileNotFound.new("Cannot symlink #{src} to #{dest} before migrate: #{e.message}")
      end
    end
    
    bash "mytardis_buildout_install" do
      user "mytardis"
      cwd current_release
      code <<-EOH
        python setup.py clean
        find . -name '*.py[co]' -delete
        python bootstrap.py -c buildout-prod.cfg -v 1.7.0
        bin/buildout -c buildout-prod.cfg install
      EOH
    end
    ruby_block "mytardis_migration_check" do
      block do
        # See if there are potentially dangerous migrations to be performed.
        if !allow_migrations then
          cmd = Mixlib::ShellOut.new(%Q[ bin/django migrate --list ],
                                     :cwd => current_release,
                                     :user => 'mytardis'
                                     ).run_command
          # Check the listing of migrations for any unapplied migration that
          # is not an '0001' (initial) migration.  If we can't list the
          # the migrations at all, we most likely have a brand new (empty)
          # database.
          if cmd.exitstatus == 0 and
              cmd.stdout =~ /\( \) +(?!0001_initial)[^ ].*/ then
            Chef::Application.fatal!(
                                     "A potentially dangerous South migration has been detected: #{$&}\n" +
                                     "For advice on how to proceed, refer to the MyTardis chef cookbook documentation\n")
          end
        end
      end
    end
  end
  migration_command "bin/django syncdb --noinput --migrate &&" + 
                    "bin/django collectstatic -l --noinput"

  # The foreman restart needs to be run as root, so we can't use 
  # the 'restart_command' attribute
  before_restart do
    current_release = release_path

    bash "mytardis_foreman_install_and_restart" do
      cwd current_release
      code <<-EOH
        foreman export upstart /etc/init -a mytardis -p 3031 -u mytardis -l /var/log/mytardis
        cat >> /etc/init/mytardis-uwsgi-1.conf <<EOZ
post-stop script
  pkill uwsgi
  sleep 2
  pkill -9 uwsgi
end script
EOZ
        restart mytardis || start mytardis
      EOH
    end
  end
end

if backups then
  include_recipe "mytardis::backups"
end

