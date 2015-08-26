class AddTabConfigurationToGroups < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :groups, :tab_configuration, :text
    add_column :groups, :dynamic_tab_configuration, :text
  end

  def self.down
    remove_column :groups, :tab_configuration
    remove_column :groups, :dynamic_tab_configuration
  end
end
