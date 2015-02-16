class AddSectionForQuizzes < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :quizzes, :course_section_id, :integer, :limit => 8
    add_index :quizzes, :course_section_id
    add_foreign_key_if_not_exists :quizzes, :course_sections
  end

  def self.down
    remove_foreign_key :quizzes, :course_sections
    remove_index :quizzes, :course_section_id
    remove_column :quizzes, :course_section_id
  end
end
