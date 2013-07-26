role :app,      "hotchalklearn.com"
role :db,       "hotchalklearn.com", :primary => true

set :bundle_without, [:sqlite]

set :rails_env, "production"
