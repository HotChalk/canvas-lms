require "bundler/capistrano"

set :stages,        %w(production qa)
set :default_stage, "qa"
require "capistrano/ext/multistage"

set :application,   "Canvas"
set :repository,    "git@github.com:/HotChalk/canvas-lms.git"
set :scm,           :git
set :user,          "canvasuser"
set :branch,        "master"
set :deploy_via,    :remote_cache
set :deploy_to,     "/srv/canvas"
set :use_sudo,      false
set :rake,          "bundle exec rake"

set :ssh_options, {:forward_agent => true}
ssh_options[:keys] = [File.join(ENV["HOME"], ".ssh", "hotchalk.pem")]
set :git_enable_submodules, 1

namespace :deploy do
  task :start do ; end
  task :stop do ; end
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
  end
end

# Canvas-specific task after a deploy
namespace :canvas do

  # On every deploy
  desc "Create symlink for files folder to mount point"
  task :files_symlink do
    folder = 'tmp/files'
    run "ln -s /srv/data/files #{latest_release}/#{folder}"
  end

  desc "Compile static assets"
  task :compile_assets, :on_error => :continue do
    # On remote: bundle exec rake canvas:compile_assets
    run "cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} canvas:compile_assets --quiet"
    run "cd #{latest_release} && chown -R canvasuser:canvas ."
  end

  desc "Copy shared config files"
  task :config_copy do
    folder = 'config'
    run "rm -rf #{latest_release}/#{folder}/*"
    run "cp -R /srv/canvas/shared/config/* #{latest_release}/#{folder}"
  end

  # Updates only
  desc "Post-update commands"
  task :update_remote do
    deploy.migrate
    load_notifications
    restart_jobs
    puts "\x1b[42m\x1b[1;37m Deploy complete!  \x1b[0m"
  end

  desc "Load new notification types"
  task :load_notifications, :roles => :db, :only => { :primary => true } do
    # On remote: RAILS_ENV=production bundle exec rake db:load_notifications
    run "cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} db:load_notifications --quiet"
  end
  
  desc "Restarted delayed jobs workers"
  task :restart_jobs, :on_error => :continue do
    # On remote: /etc/init.d/canvas_init restart
    run "/etc/init.d/canvas_init restart"
  end
  
end

after(:deploy, "deploy:cleanup")
before("deploy:restart", "canvas:files_symlink")
before("deploy:restart", "canvas:config_copy")
before("deploy:restart", "canvas:compile_assets")
