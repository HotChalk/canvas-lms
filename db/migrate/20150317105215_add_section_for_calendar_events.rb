class AddSectionForCalendarEvents < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :calendar_events, :course_section_id, :integer, :limit => 8
    add_index :calendar_events, :course_section_id
    add_foreign_key_if_not_exists :calendar_events, :course_sections
  end

  def self.down
    remove_foreign_key :calendar_events, :course_sections
    remove_index :calendar_events, :course_section_id
    remove_column :calendar_events, :course_section_id
  end
end
