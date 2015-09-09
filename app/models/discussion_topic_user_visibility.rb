class DiscussionTopicUserVisibility < ActiveRecord::Base
  # necessary for general_model_spec
  attr_protected :user, :discussion_topic, :course

  include VisibilityPluckingHelper

  belongs_to :user
  belongs_to :discussion_topic
  belongs_to :course

  # create_or_update checks for !readonly? before persisting
  def readonly?
    true
  end

  def self.visible_discussion_topic_ids_in_course_by_user(opts)
    visible_object_ids_in_course_by_user(:discussion_topic_id, opts)
  end

  def self.users_with_visibility_by_discussion_topic(opts)
    users_with_visibility_by_object_id(:discussion_topic_id, opts)
  end

  def self.visible_discussion_topic_ids_for_user(user_id, course_ids=nil)
    opts = {user_id: user_id}
    if course_ids
      opts[:course_id] = course_ids
    end
    self.where(opts).pluck(:discussion_topic)
  end

  # readonly? is not checked in destroy though
  before_destroy { |record| raise ActiveRecord::ReadOnlyRecord }
end
