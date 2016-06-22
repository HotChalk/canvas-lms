class AddCertificateTextToAccountAuthorizationConfigs < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :account_authorization_configs, :certificate_text, :text
  end

  def self.down
    drop_column :account_authorization_configs, :certificate_text
  end
end
