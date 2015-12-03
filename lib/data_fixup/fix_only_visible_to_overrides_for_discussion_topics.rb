module DataFixup::FixOnlyVisibleToOverridesForDiscussionTopics
  def self.run
    # Process discussion topics that have a matching assignment override record, but do not have the only_visible_to_overrides flag set to true
    DiscussionTopic.
      joins("INNER JOIN assignment_overrides ON assignment_overrides.discussion_topic_id = discussion_topics.id
              AND assignment_overrides.workflow_state = 'active'").
      where("(discussion_topics.only_visible_to_overrides IS NULL OR discussion_topics.only_visible_to_overrides = false) AND discussion_topics.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |topic|
        topic.only_visible_to_overrides = true
        topic.save_without_broadcasting!
      end
    end
    # Process discussion topics that have associated assignments with the only_visible_to_overrides flag set to true
    DiscussionTopic.
      joins("INNER JOIN assignments ON discussion_topics.assignment_id = assignments.id
              AND assignments.workflow_state <> 'deleted' AND assignments.only_visible_to_overrides = true").
      where("(discussion_topics.only_visible_to_overrides IS NULL OR discussion_topics.only_visible_to_overrides = false) AND discussion_topics.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |topic|
        topic.only_visible_to_overrides = true
        topic.save_without_broadcasting!
      end
    end
  end
end