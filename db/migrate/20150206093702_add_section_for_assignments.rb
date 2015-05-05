class AddSectionForAssignments < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :assignments, :course_section_id, :integer, :limit => 8
    add_index :assignments, :course_section_id
    add_foreign_key_if_not_exists :assignments, :course_sections
  end

  def self.down
    remove_foreign_key :assignments, :course_sections
    remove_index :assignments, :course_section_id
    remove_column :assignments, :course_section_id
  end
end
