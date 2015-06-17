class AddSectionToGroups < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :groups, :course_section_id, :integer, :limit => 8
    add_index :groups, :course_section_id
    add_foreign_key_if_not_exists :groups, :course_sections
  end

  def self.down
    remove_foreign_key :groups, :course_sections
    remove_index :groups, :course_section_id
    remove_column :groups, :course_section_id
  end
end
