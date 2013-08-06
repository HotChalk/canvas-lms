class AddHmacToAccountAuthorizationConfig < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :account_authorization_configs, :hmac_shared_secret, :string
    add_column :account_authorization_configs, :hmac_timestamp_range, :integer
  end

  def self.down
    remove_column :account_authorization_configs, :hmac_shared_secret
    remove_column :account_authorization_configs, :hmac_timestamp_range
  end
end
