class RemoveCustomSections < ActiveRecord::Migration
  tag :postdeploy

  def up
    # Drop views
    self.connection.execute "DROP VIEW discussion_topic_user_visibilities;"
    self.connection.execute "DROP VIEW quiz_user_visibilities;"
    self.connection.execute "DROP VIEW assignment_user_visibilities;"

    # Drop constraints
    remove_foreign_key :assignment_override_students, :discussion_topic
    remove_foreign_key :assignment_overrides, :discussion_topic
    remove_foreign_key :assignments, :course_sections
    remove_foreign_key :calendar_events, :course_sections
    remove_foreign_key :discussion_topics, :course_sections
    remove_foreign_key :discussion_topics, :reply_assignment
    remove_foreign_key :groups, :course_sections
    remove_foreign_key :quizzes, :course_sections

    # Drop indices
    remove_index :assignment_override_students, :discussion_topic_id
    remove_index :assignment_overrides, :discussion_topic_id
    remove_index :assignments, :course_section_id
    remove_index :calendar_events, :course_section_id
    remove_index :discussion_topics, :course_section_id
    remove_index :groups, :course_section_id
    remove_index :quizzes, :course_section_id

    # Drop columns
    remove_column :assignment_override_students, :discussion_topic_id
    remove_column :assignment_overrides, :discussion_topic_id
    remove_column :assignments, :course_section_id
    remove_column :groups, :course_section_id
    remove_column :calendar_events, :course_section_id
    remove_column :discussion_topics, :grade_replies_separately
    remove_column :discussion_topics, :reply_assignment_id
    remove_column :discussion_topics, :course_section_id
    remove_column :discussion_topics, :only_visible_to_overrides
    remove_column :quizzes, :course_section_id
  end

  def down
  end
end
