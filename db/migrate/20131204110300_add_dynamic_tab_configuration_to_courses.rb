class AddDynamicTabConfigurationToCourses < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :courses, :dynamic_tab_configuration, :text
  end

  def self.down
    remove_column :courses, :dynamic_tab_configuration
  end
end