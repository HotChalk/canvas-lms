class AddAdhocOverridesToDiscussionTopicUserVisibilityView < ActiveRecord::Migration
  tag :predeploy

  def up
    self.connection.execute "DROP VIEW discussion_topic_user_visibilities;"
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

      LEFT JOIN assignment_overrides ao
        ON ao.discussion_topic_id = d.id
        AND ao.workflow_state = 'active'
        AND (
          (ao.set_type = 'CourseSection' AND ao.set_id = cs.id)
          OR (
            (ao.set_type = 'ADHOC' AND ao.set_id IS NULL)
            AND EXISTS (
              SELECT 1
              FROM assignment_override_students aos
                INNER JOIN enrollments ste ON aos.user_id = ste.user_id AND ste.workflow_state != 'deleted' AND ste.course_section_id = cs.id
			        WHERE aos.discussion_topic_id = d.id
			          AND aos.assignment_override_id = ao.id
                AND (
                  (aos.user_id = e.user_id)
                  OR (e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment'))
                )
            )
          )
        )

      WHERE d.workflow_state != 'deleted'
        AND (d.workflow_state != 'unpublished' OR (e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment')))
        AND (
          (d.only_visible_to_overrides = 'true' AND ao.id IS NOT NULL)
          OR (COALESCE(d.only_visible_to_overrides, 'false') = 'false')
        )
      )
  end

  def down
    self.connection.execute "DROP VIEW discussion_topic_user_visibilities;"
  end
end
