class AddDiscussionTopicIdToAssignmentOverrides < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :assignment_overrides, :discussion_topic_id, :integer, :limit => 8
    add_index :assignment_overrides, :discussion_topic_id
    add_foreign_key_if_not_exists :assignment_overrides, :discussion_topics
  end

  def self.down
    remove_foreign_key_if_exists :assignment_overrides, :discussion_topics
    remove_index :assignment_overrides, :discussion_topic_id
    remove_column :assignment_overrides, :discussion_topic_id
  end
end