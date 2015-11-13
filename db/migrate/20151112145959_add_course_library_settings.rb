class AddCourseLibrarySettings < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :wiki_pages, :course_library_settings, :text
    add_column :assignments, :course_library_settings, :text
    add_column :discussion_topics, :course_library_settings, :text
    add_column :quizzes, :course_library_settings, :text
  end

  def self.down
    remove_column :wiki_pages, :course_library_settings
    remove_column :assignments, :course_library_settings
    remove_column :discussion_topics, :course_library_settings
    remove_column :quizzes, :course_library_settings
  end
end
