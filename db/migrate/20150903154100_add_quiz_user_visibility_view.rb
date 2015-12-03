class AddQuizUserVisibilityView < ActiveRecord::Migration
  tag :predeploy

  def self.up
    self.connection.execute %Q(CREATE VIEW quiz_user_visibilities AS
      (SELECT qsv.* FROM quiz_student_visibilities AS qsv)
      UNION ALL
      (
        SELECT DISTINCT q.id as quiz_id,
        e.user_id as user_id,
        c.id as course_id

        FROM quizzes q

        JOIN courses c
          ON q.context_id = c.id
          AND q.context_type = 'Course'

        JOIN enrollments e
          ON e.course_id = c.id
          AND e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment')
          AND e.workflow_state != 'deleted'

        JOIN course_sections cs
          ON cs.course_id = c.id
          AND e.course_section_id = cs.id

        LEFT JOIN assignment_overrides ao
          ON ao.quiz_id = q.id
          AND ao.workflow_state = 'active'
          AND ao.set_type = 'CourseSection'
          AND ao.set_id = cs.id

        LEFT JOIN assignments a
          ON a.context_id = q.context_id
          AND a.submission_types LIKE 'online_quiz'
          AND a.id = q.assignment_id

        WHERE q.workflow_state NOT IN ('deleted','unpublished')
          AND (
            (q.only_visible_to_overrides = 'true' AND ao.id IS NOT NULL)
            OR (COALESCE(q.only_visible_to_overrides, 'false') = 'false')
          )
      )
    )
  end

  def self.down
    self.connection.execute "DROP VIEW quiz_user_visibilities;"
  end
end
