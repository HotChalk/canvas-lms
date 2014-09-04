class AddSectionForAnnouncements < ActiveRecord::Migration
  tag :predeploy
  disable_ddl_transaction!

  def self.up
    add_column :discussion_topics, :course_section_id, :integer, :limit => 8
    add_index :discussion_topics, :course_section_id
    add_foreign_key_if_not_exists :discussion_topics, :course_sections
  end

  def self.down
    remove_foreign_key :discussion_topics, :course_sections
    remove_index :discussion_topics, :course_section_id
    remove_column :discussion_topics, :course_section_id
  end
end
