class AddReplyAssignmentToDiscussionTopics < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :discussion_topics, :grade_replies_separately, :boolean, :default => false
    DiscussionTopic.update_all :grade_replies_separately => false
    add_column :discussion_topics, :reply_assignment_id, :integer, :limit => 8
    add_foreign_key_if_not_exists :discussion_topics, :assignments, :column => :reply_assignment_id, :delay_validation => true
  end

  def self.down
    remove_foreign_key_if_exists :discussion_topics, :column => :reply_assignment_id
    remove_column :discussion_topics, :grade_replies_separately
    remove_column :discussion_topics, :reply_assignment_id
  end
end
