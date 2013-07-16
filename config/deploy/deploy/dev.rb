server 'canvas-lms', :app, :web, :primary => true
set :rails_env,		"development"
set :deploy_env,	"development"
set :bundle_without,  	[:production, :test]
