class AddOnlyVisibleToOverridesToDiscussionTopics < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :discussion_topics, :only_visible_to_overrides, :boolean
  end

  def self.down
    remove_column :discussion_topics, :only_visible_to_overrides
  end
end
