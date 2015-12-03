class AddDiscussionTopicVisibilityView < ActiveRecord::Migration
  tag :predeploy

  def self.up
    self.connection.execute %Q(CREATE VIEW discussion_topic_user_visibilities AS
      SELECT DISTINCT d.id as discussion_topic_id,
      e.user_id as user_id,
      c.id as course_id

      FROM discussion_topics d

      JOIN courses c
        ON d.context_id = c.id
        AND d.context_type = 'Course'

      JOIN enrollments e
        ON e.course_id = c.id
        AND e.type IN ('StudentEnrollment', 'StudentViewEnrollment', 'TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment')
        AND e.workflow_state != 'deleted'

      JOIN course_sections cs
        ON cs.course_id = c.id
        AND e.course_section_id = cs.id

      LEFT JOIN assignment_override_students aos
        ON aos.discussion_topic_id = d.id
        AND aos.user_id = e.user_id

      LEFT JOIN assignment_overrides ao
        ON ao.discussion_topic_id = d.id
        AND ao.workflow_state = 'active'
        AND (
          (ao.set_type = 'CourseSection' AND ao.set_id = cs.id)
          OR (ao.set_type = 'ADHOC' AND ao.set_id IS NULL AND ao.id = aos.assignment_override_id)
        )

      WHERE d.workflow_state NOT IN ('deleted','unpublished')
        AND ao.id IS NOT NULL
      )
  end

  def self.down
    self.connection.execute "DROP VIEW discussion_topic_user_visibilities;"
  end
end