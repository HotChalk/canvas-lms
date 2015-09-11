class AddAssignmentUserVisibilityView < ActiveRecord::Migration
  tag :predeploy

  def up
    self.connection.execute %Q(CREATE VIEW assignment_user_visibilities AS
      (SELECT asv.* FROM assignment_student_visibilities AS asv)
      UNION ALL
      (
        SELECT DISTINCT a.id as assignment_id,
        e.user_id as user_id,
        c.id as course_id

        FROM assignments a

        JOIN courses c
          ON a.context_id = c.id
          AND a.context_type = 'Course'

        JOIN enrollments e
          ON e.course_id = c.id
          AND e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment')
          AND e.workflow_state != 'deleted'

        JOIN course_sections cs
          ON cs.course_id = c.id
          AND e.course_section_id = cs.id

        LEFT JOIN assignment_overrides ao
          ON ao.assignment_id = a.id
          AND ao.workflow_state = 'active'
          AND ao.set_type = 'CourseSection'
          AND ao.set_id = cs.id

        WHERE a.workflow_state NOT IN ('deleted','unpublished')
          AND (
            (a.only_visible_to_overrides = 'true' AND ao.id IS NOT NULL)
            OR (COALESCE(a.only_visible_to_overrides, 'false') = 'false')
          )
      )
    )
  end

  def down
    self.connection.execute "DROP VIEW assignment_user_visibilities;"
  end
end
