role :app,      "ec2-54-218-232-89.us-west-2.compute.amazonaws.com"
role :db,       "ec2-54-218-232-89.us-west-2.compute.amazonaws.com", :primary => true

set :bundle_without, [:sqlite]

set :rails_env, "production"
