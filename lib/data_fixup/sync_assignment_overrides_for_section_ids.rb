module DataFixup::SyncAssignmentOverridesForSectionIds
  def self.run
    # Process assignments that have a course_section_id set, but do not have a matching assignment override record (this covers regular assignments and quizzes)
    Assignment.
      joins("LEFT JOIN assignment_overrides ON assignment_overrides.assignment_id = assignments.id
              AND assignment_overrides.set_id = assignments.course_section_id
              AND assignment_overrides.set_type = 'CourseSection'
              AND assignment_overrides.workflow_state = 'active'").
      where("assignments.course_section_id IS NOT NULL AND assignment_overrides.id IS NULL AND assignments.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |assignment|
        build_override(assignment.assignment_overrides, assignment.due_at, assignment.unlock_at, assignment.lock_at, assignment.course_section)
        assignment.only_visible_to_overrides = true
        assignment.save_without_broadcasting!
        if assignment.quiz?
          assignment.quiz.only_visible_to_overrides = true
          assignment.quiz.save!
        end
      end
    end
    # Process assignments that have a course_section_id set and also have a matching assignment override record, but do not have the only_visible_to_overrides flag set to true
    Assignment.
      joins("INNER JOIN assignment_overrides ON assignment_overrides.assignment_id = assignments.id
              AND assignment_overrides.set_id = assignments.course_section_id
              AND assignment_overrides.set_type = 'CourseSection'
              AND assignment_overrides.workflow_state = 'active'").
      where("assignments.course_section_id IS NOT NULL AND (assignments.only_visible_to_overrides IS NULL OR assignments.only_visible_to_overrides = false) AND assignments.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |assignment|
        assignment.only_visible_to_overrides = true
        assignment.save_without_broadcasting!
        if assignment.quiz?
          assignment.quiz.only_visible_to_overrides = true
          assignment.quiz.save!
        end
      end
    end
    # Process assignments that have at least one assignment override record for a course section, but do not have the only_visible_to_overrides flag set to true
    Assignment.
      where("EXISTS (SELECT 1 FROM assignment_overrides
              WHERE assignment_overrides.assignment_id = assignments.id
              AND assignment_overrides.set_type = 'CourseSection'
              AND assignment_overrides.workflow_state = 'active')
              AND assignments.only_visible_to_overrides IS NULL AND assignments.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |assignment|
        assignment.only_visible_to_overrides = true
        assignment.save_without_broadcasting!
        if assignment.quiz?
          assignment.quiz.only_visible_to_overrides = true
          assignment.quiz.save!
        end
      end
    end
    # Process discussion topics that have a course_section_id set but are not linked to an assignment
    DiscussionTopic.
      joins("LEFT JOIN assignment_overrides ON assignment_overrides.discussion_topic_id = discussion_topics.id
              AND assignment_overrides.set_id = discussion_topics.course_section_id
              AND assignment_overrides.set_type = 'CourseSection'
              AND assignment_overrides.workflow_state = 'active'").
      where("discussion_topics.course_section_id IS NOT NULL AND discussion_topics.assignment_id IS NULL AND assignment_overrides.id IS NULL AND discussion_topics.workflow_state <> 'deleted'").
      readonly(false).
      find_in_batches(batch_size: 100) do |group|
      group.each do |topic|
        build_override(topic.assignment_overrides, nil, topic.delayed_post_at, topic.lock_at, topic.course_section)
      end
    end
  end

  def self.build_override(collection, due_at, unlock_at, lock_at, section)
    override = collection.build
    override.title = section.name
    override.set = section
    override.set_type = 'CourseSection'
    override.due_at = due_at
    override.unlock_at = unlock_at
    override.lock_at = lock_at
    override.due_at_overridden = true
    override.lock_at_overridden = true
    override.unlock_at_overridden = true
    override.save_without_broadcasting!
    override
  end
end