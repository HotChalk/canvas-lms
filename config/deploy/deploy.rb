require "bundler/capistrano"

set :stages,        %w(production dev)
set :default_stage, "production"
require "capistrano/ext/multistage"

set :application,   "Canvas"
set :repository,    "git@github.com:/HotChalk/canvas-lms.git"
set :scm,           :git
set :user,          "canvasuser"
set :branch,        "master"
set :deploy_via,    :remote_cache
set :deploy_to,     "/srv/canvas"
set :use_sudo,      false
set :deploy_env,    "production"


task :uname do
  run 'uname -a'
end

namespace :deploy do
  task :start do ; end
  task :stop do ; end
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
  end
end

# Canvas-specific task after a deploy
namespace :canvas do
  
  # LOCAL COMMANDS
  desc "Update the master branch of the local repo"
  task :update do
    check_user
    stashResponse = run_locally "git stash"
    puts stashResponse
    puts run_locally "git checkout master"
    puts run_locally "git fetch"
    puts run_locally "git merge origin/master"
    puts run_locally "git stash pop" unless stashResponse == "No local changes to save\n"
    puts "\x1b[42m\x1b[1;37m Update successful. You should now run 'cap canvas:update_gems' \x1b[0m"
  end
  
  desc "Install new gems from bundle and push updates"
  task :update_gems do
    check_user
    stashResponse = run_locally "git stash"
    puts stashResponse
    puts run_locally "bundle install"  #--path path=~/gems"
    puts run_locally "git add Gemfile.lock"
    puts run_locally "git commit --allow-empty Gemfile.lock -m 'Add Gemfile.lock for deploy #{release_name}'"
    puts run_locally "git push origin"
    puts run_locally "git stash pop" unless stashResponse == "No local changes to save\n"
    puts "\x1b[42m\x1b[1;37m Push successful. You should now run 'cap deploy' and 'cap canvas:update_remote' \x1b[0m"
  end

  # REMOTE COMMANDS

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
  
  # UTILITY TASKS
  desc "Make sure that only the deploy user can run certain tasks"
  task :check_user do
    transaction do 
      do_check_user
    end
  end

  desc "Make sure that only the deploy user can run certain tasks"
  task :do_check_user do
    on_rollback do
      puts "\x1b[41m\x1b[1;37m Please run this command as 'deploy' user \x1b[0m"
    end
    run_locally "[ `whoami` == deploy ]"
  end
end

after(:deploy, "deploy:cleanup")
before(:deploy, "canvas:check_user")
before("deploy:restart", "canvas:files_symlink")
before("deploy:restart", "canvas:compile_assets")