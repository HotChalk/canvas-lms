#
# If your target environment is configured to use an Apache Cassandra cluster,
# please keep in mind that you will need to perform some configuration changes prior
# to running this tool:
#
# 1. Edit your cassandra.yml configuration file and set a high timeout value for each keyspace, e.g.:
#    timeout: 100000
#
# 2. Create the following indexes in your Cassandra cluster:
#    CREATE INDEX page_views_account_id_idx ON page_views.page_views (account_id);
#    CREATE INDEX page_views_history_by_context_request_id_idx ON page_views.page_views_history_by_context (request_id);
#    CREATE INDEX participations_by_context_request_id_idx ON page_views.participations_by_context (request_id);
#
# Index creation can be a long-running process, so you should verify that the indexes have
# been successfully created by querying the affected tables using a WHERE condition for the request_id column.
#
class AccountRemover
  def initialize(opts)
    @include_postgres = opts[:postgres]
    @include_cassandra = opts[:cassandra]
    @explain = opts[:explain]
    @truncate_messages = opts[:truncate_messages]
    @drop_keys = opts[:drop_keys]
    raise "Must include at least one repository for data deletion: Postgres, Cassandra or both" unless @include_postgres || @include_cassandra
    raise "Cassandra is not enabled for this environment" if @include_cassandra && !cassandra?
    @account = opts[:account_id] && Account.find(opts[:account_id])
    raise "Account not found: #{opts[:account_id]}" unless @account.present?
    raise "Account is not a root account: #{opts[:account_id]}" unless @account.root_account?
    raise "Account is default root account or Site Admin: #{opts[:account_id]}" if Account.special_accounts.include?(@account)
  end

  def run
    Rails.logger.info "[ACCOUNT-REMOVER] Deleting root account #{@account.name} [#{@account.id}]..."
    begin
      real_time = Benchmark.realtime do
        # Collect some convenient data points
        @all_account_ids = (@account.all_accounts.pluck(:id) << @account.id)
        @all_user_ids = Pseudonym.where(:account_id => @all_account_ids).pluck(:user_id).uniq - Pseudonym.where.not(:account_id => @all_account_ids).pluck(:user_id).uniq
        @all_course_ids = Course.where(:root_account_id => @account.id).pluck(:id)

        # Delete data in Cassandra
        if cassandra?
          delete_in_cassandra
        end

        # Delete object graph in Postgres
        if postgres?
          prepare_data
          drop_foreign_keys
          @account.transaction do
            delete_in_postgres
          end
        end
      end
      Rails.logger.info "[ACCOUNT-REMOVER] Successfully deleted root account #{@account.name} [#{@account.id}] in #{real_time.to_i}s"
    rescue Exception => e
      Rails.logger.error "[ACCOUNT-REMOVER] Account removal failed: #{e.inspect}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      recreate_foreign_keys
    end
  end

  def drop_foreign_keys
    if @drop_keys
      Rails.logger.info "[ACCOUNT-REMOVER] Dropping foreign keys..."
      real_time = Benchmark.realtime do
        sql = <<-SQL
          SELECT
            (quote_ident(ns.nspname) || '.' || quote_ident(tb.relname)) AS tbl_name,
            quote_ident(conname) AS key_name,
            pg_get_constraintdef(c.oid, true) AS ddl
          FROM pg_constraint c
            INNER JOIN pg_class tb ON tb.oid = c.conrelid
            INNER JOIN pg_namespace ns ON ns.oid = tb.relnamespace
          WHERE ns.nspname = 'public' AND c.contype = 'f';
        SQL
        @foreign_keys = ActiveRecord::Base.connection.exec_query(sql).map {|row| row.symbolize_keys}
        @foreign_keys.each do |key_data|
          ActiveRecord::Base.connection.execute("ALTER TABLE #{key_data[:tbl_name]} DROP CONSTRAINT #{key_data[:key_name]}")
        end
      end
      Rails.logger.info "[ACCOUNT-REMOVER] Finished dropping foreign keys in #{real_time} seconds."
    end
  end

  def recreate_foreign_keys
    if @drop_keys
      Rails.logger.info "[ACCOUNT-REMOVER] Recreating foreign keys..."
      real_time = Benchmark.realtime do
        @foreign_keys.each do |key_data|
          ActiveRecord::Base.connection.execute("ALTER TABLE #{key_data[:tbl_name]} ADD CONSTRAINT #{key_data[:key_name]} #{key_data[:ddl]}")
        end
      end
      Rails.logger.info "[ACCOUNT-REMOVER] Finished recreating foreign keys in #{real_time} seconds."
    end
  end

  def delete_in_cassandra
    Rails.logger.info "[ACCOUNT-REMOVER] Deleting data in Cassandra..."
    real_time = Benchmark.realtime do
      @all_account_ids.each do |account_id|
        Rails.logger.info "[ACCOUNT-REMOVER] Deleting account #{account_id} in Cassandra..."
        delete_account_from_cassandra(account_id)
      end
      @all_course_ids.each do |course_id|
        Rails.logger.info "[ACCOUNT-REMOVER] Deleting course #{course_id} in Cassandra..."
        delete_course_from_cassandra(course_id)
        user_ids = Enrollment.where(:course_id => course_id).pluck(:user_id).uniq
        user_ids.each {|user_id| delete_enrollment_from_cassandra(course_id, user_id)}
      end
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished deleting data in Cassandra in #{real_time.to_i} seconds."
  end

  def timed_exec(statement)
    if @explain
      plan_rows = ActiveRecord::Base.connection.exec_query("EXPLAIN #{statement}").rows
      Rails.logger.info "[ACCOUNT-REMOVER] PLAN: #{statement}}"
      Rails.logger << plan_rows.flatten.join("\n")
      Rails.logger << "\n"
    end
    real_time = Benchmark.realtime do
      ActiveRecord::Base.connection.execute(statement)
    end
    Rails.logger.info "[ACCOUNT-REMOVER] [#{real_time.to_i}s] EXEC: #{statement}"
  end

  def prepare_data
    Rails.logger.info "[ACCOUNT-REMOVER] Preparing data in Postgres..."
    real_time = Benchmark.realtime do
      # Create temporary table with all account IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_accounts (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_accounts (id) VALUES #{@all_account_ids.map {|id| "(#{id})"}.join(',')}")

      # Create temporary table with all user IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_users (id BIGINT NOT NULL PRIMARY KEY)")
      @all_user_ids.each_slice(100) do |batch_ids|
        ActiveRecord::Base.connection.execute("INSERT INTO delete_users (id) VALUES #{batch_ids.map {|id| "(#{id})"}.join(',')}")
      end

      # Create temporary table with all course IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_courses AS SELECT c.id FROM courses c WHERE c.root_account_id = #{@account.id}")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_courses ADD PRIMARY KEY (id)")

      # Create temporary table with all discussion topic IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_groups (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_groups SELECT g.id FROM groups g INNER JOIN delete_accounts d ON g.context_type = 'Account' AND g.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_groups SELECT g.id FROM groups g INNER JOIN delete_courses d ON g.context_type = 'Course' AND g.context_id = d.id")

      # Create temporary table with all assignment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_assignments AS SELECT a.id FROM assignments a INNER JOIN delete_courses d ON a.context_type = 'Course' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_assignments ADD PRIMARY KEY (id)")

      # Create temporary table with all discussion topic IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_discussion_topics (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_discussion_topics (
            SELECT t.id FROM discussion_topics t INNER JOIN delete_courses d ON t.context_type = 'Course' AND t.context_id = d.id
            UNION
            SELECT t.id FROM discussion_topics t INNER JOIN delete_groups d ON t.context_type = 'Group' AND t.context_id = d.id
            UNION
            SELECT t.id FROM discussion_topics t INNER JOIN delete_users d ON t.user_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all discussion entry IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_discussion_entries (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_discussion_entries (
            SELECT e.id FROM discussion_entries e INNER JOIN delete_discussion_topics d ON e.discussion_topic_id = d.id
            UNION
            SELECT e.id FROM discussion_entries e INNER JOIN delete_users d ON e.user_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all quiz IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_quizzes AS SELECT q.id FROM quizzes q INNER JOIN delete_courses d ON q.context_type = 'Course' AND q.context_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_quizzes ADD PRIMARY KEY (id)")

      # Create temporary table with all submission IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_submissions (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_submissions (
            SELECT s.id FROM submissions s INNER JOIN delete_assignments d ON s.assignment_id = d.id
            UNION
            SELECT s.id FROM submissions s INNER JOIN delete_users d ON s.user_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all submission comment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_submission_comments (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_submission_comments (
            SELECT c.id FROM submission_comments c INNER JOIN delete_submissions d ON c.submission_id = d.id
            UNION
            SELECT c.id FROM submission_comments c INNER JOIN delete_users d ON c.author_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all assignment override IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_assignment_overrides (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_assignment_overrides (
            SELECT a.id FROM assignment_overrides a INNER JOIN delete_assignments d ON a.assignment_id = d.id
            UNION
            SELECT a.id FROM assignment_overrides a INNER JOIN delete_quizzes d ON a.quiz_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all assessment question bank IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_assessment_question_banks (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_assessment_question_banks SELECT b.id FROM assessment_question_banks b INNER JOIN delete_accounts d ON b.context_type = 'Account' AND b.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_assessment_question_banks SELECT b.id FROM assessment_question_banks b INNER JOIN delete_courses d ON b.context_type = 'Course' AND b.context_id = d.id")

      # Create temporary table with all assessment question IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_assessment_questions AS SELECT q.id FROM assessment_questions q INNER JOIN delete_assessment_question_banks d ON q.assessment_question_bank_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_assessment_questions ADD PRIMARY KEY (id)")

      # Create temporary table with all conversation IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_conversations (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_conversations SELECT c.id FROM conversations c WHERE ((c.context_type = 'Account' AND c.context_id = #{@account.id}) OR c.context_id IS NULL) AND c.root_account_ids = CAST(#{@account.id} AS TEXT)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_conversations SELECT c.id FROM conversations c INNER JOIN delete_courses d ON c.context_type = 'Course' AND c.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_conversations SELECT c.id FROM conversations c INNER JOIN delete_groups d ON c.context_type = 'Group' AND c.context_id = d.id")

      # Create temporary table with all conversation message IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_conversation_messages (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_conversation_messages (
          SELECT m.id FROM conversation_messages m INNER JOIN delete_conversations d ON m.conversation_id = d.id
          UNION
          SELECT m.id FROM conversation_messages m INNER JOIN delete_users d ON m.author_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all rubric IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_rubrics (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_rubrics SELECT r.id FROM rubrics r INNER JOIN delete_accounts d ON r.context_type = 'Account' AND r.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_rubrics SELECT r.id FROM rubrics r INNER JOIN delete_courses d ON r.context_type = 'Course' AND r.context_id = d.id")

      # Create temporary table with all rubric association IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_rubric_associations AS SELECT a.id FROM delete_rubrics r INNER JOIN rubric_associations a ON r.id = a.rubric_id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_rubric_associations ADD PRIMARY KEY (id)")

      # Create temporary table with all rubric assessment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_rubric_assessments (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_rubric_assessments (
          SELECT a.id FROM rubric_assessments a INNER JOIN delete_users d ON a.user_id = d.id
          UNION
          SELECT a.id FROM rubric_assessments a INNER JOIN delete_users d ON a.assessor_id = d.id
          UNION
          SELECT a.id FROM rubric_assessments a INNER JOIN delete_rubric_associations d ON a.rubric_association_id = d.id
          UNION
          SELECT a.id FROM rubric_assessments a INNER JOIN delete_rubrics d ON a.rubric_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all collaboration IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_collaborations (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_collaborations SELECT c.id FROM collaborations c INNER JOIN delete_courses d ON c.context_type = 'Course' AND c.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_collaborations SELECT c.id FROM collaborations c INNER JOIN delete_groups d ON c.context_type = 'Group' AND c.context_id = d.id")

      # Create temporary table with all context external tool IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_context_external_tools (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_context_external_tools SELECT t.id FROM context_external_tools t INNER JOIN delete_accounts d ON t.context_type = 'Account' AND t.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_context_external_tools SELECT t.id FROM context_external_tools t INNER JOIN delete_courses d ON t.context_type = 'Course' AND t.context_id = d.id")

      # Create temporary table with all context module IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_context_modules AS SELECT m.id FROM context_modules m INNER JOIN delete_courses d ON m.context_type = 'Course' AND m.context_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_context_modules ADD PRIMARY KEY (id)")

      # Create temporary table with all enrollment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_enrollments (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_enrollments (
          SELECT e.id FROM enrollments e INNER JOIN delete_courses d ON e.course_id = d.id
          UNION
          SELECT e.id FROM enrollments e INNER JOIN delete_users d ON e.user_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all eportfolio IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_eportfolios AS SELECT p.id FROM eportfolios p INNER JOIN delete_users d ON p.user_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_eportfolios ADD PRIMARY KEY (id)")

      # Create temporary table with all external feed IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_external_feeds (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_external_feeds SELECT f.id FROM external_feeds f INNER JOIN delete_courses d ON f.context_type = 'Course' AND f.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_external_feeds SELECT f.id FROM external_feeds f INNER JOIN delete_groups d ON f.context_type = 'Group' AND f.context_id = d.id")

      # Create temporary table with all learning outcome IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_learning_outcomes (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_learning_outcomes SELECT o.id FROM learning_outcomes o INNER JOIN delete_accounts d ON o.context_type = 'Account' AND o.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_learning_outcomes SELECT o.id FROM learning_outcomes o INNER JOIN delete_courses d ON o.context_type = 'Course' AND o.context_id = d.id")

      # Create temporary table with all learning outcome result IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_learning_outcome_results (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_learning_outcome_results SELECT r.id FROM learning_outcome_results r INNER JOIN delete_learning_outcomes d ON r.learning_outcome_id = d.id")

      # Create temporary table with all content migration IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_content_migrations (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_content_migrations (
            SELECT m.id FROM content_migrations m INNER JOIN delete_courses d ON m.source_course_id = d.id
            UNION
            SELECT m.id FROM content_migrations m INNER JOIN delete_courses d ON m.context_type = 'Course' AND m.context_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)
      ActiveRecord::Base.connection.execute("INSERT INTO delete_content_migrations SELECT m.id FROM content_migrations m INNER JOIN delete_groups d ON m.context_type = 'Group' AND m.context_id = d.id")

      # Create temporary table with all quiz submission IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_quiz_submissions (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
          INSERT INTO delete_quiz_submissions (
            SELECT s.id FROM quiz_submissions s INNER JOIN delete_quizzes d ON s.quiz_id = d.id
            UNION
            SELECT s.id FROM quiz_submissions s INNER JOIN delete_users d ON s.user_id = d.id
          )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all quiz statistics IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_quiz_statistics AS SELECT s.id FROM quiz_statistics s INNER JOIN delete_quizzes d ON s.quiz_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_quiz_statistics ADD PRIMARY KEY (id)")

      # Create temporary table with all stream item IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_stream_items (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_stream_items SELECT s.id FROM stream_items s INNER JOIN delete_accounts d ON s.context_type = 'Account' AND s.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_stream_items SELECT s.id FROM stream_items s INNER JOIN delete_assignment_overrides d ON s.context_type = 'AssignmentOverride' AND s.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_stream_items SELECT s.id FROM stream_items s INNER JOIN delete_courses d ON s.context_type = 'Course' AND s.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_stream_items SELECT s.id FROM stream_items s INNER JOIN delete_groups d ON s.context_type = 'Group' AND s.context_id = d.id")

      # Create temporary table with all content export IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_content_exports (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_content_exports (
          SELECT e.id FROM content_exports e INNER JOIN delete_courses d ON e.context_type = 'Course' AND e.context_id = d.id
          UNION
          SELECT e.id FROM content_exports e INNER JOIN delete_groups d ON e.context_type = 'Group' AND e.context_id = d.id
          UNION
          SELECT e.id FROM content_exports e INNER JOIN delete_users d ON e.context_type = 'User' AND e.context_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all SIS batch IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_sis_batches (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_sis_batches (
          SELECT s.id FROM sis_batches s INNER JOIN delete_accounts d ON s.account_id = d.id
          UNION
          SELECT s.id FROM sis_batches s INNER JOIN delete_users d ON s.user_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all gradebook upload IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_gradebook_uploads AS SELECT u.id FROM gradebook_uploads u INNER JOIN delete_courses d ON u.course_id = d.id")
      ActiveRecord::Base.connection.execute("ALTER TABLE delete_gradebook_uploads ADD PRIMARY KEY (id)")

      # Create temporary table with all calendar event IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_calendar_events (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_calendar_events (
          SELECT e.id FROM calendar_events e INNER JOIN delete_courses d ON e.context_type = 'Course' AND e.context_id = d.id
          UNION
          SELECT e.id FROM calendar_events e INNER JOIN course_sections s ON e.context_type = 'CourseSection' AND e.context_id = s.id INNER JOIN delete_courses d ON s.course_id = d.id
          UNION
          SELECT e.id FROM calendar_events e INNER JOIN delete_groups d ON e.context_type = 'Group' AND e.context_id = d.id
          UNION
          SELECT e.id FROM calendar_events e INNER JOIN delete_users d ON e.context_type = 'User' AND e.context_id = d.id
          UNION
          SELECT e.id FROM calendar_events e INNER JOIN delete_users d ON e.user_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all appointment group IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_appointment_groups (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_appointment_groups SELECT DISTINCT e.context_id FROM calendar_events e INNER JOIN delete_courses d ON e.effective_context_code = CONCAT('course_', d.id) WHERE e.context_type = 'AppointmentGroup'")

      # Create temporary table with all content export IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_folders (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_folders SELECT f.id FROM folders f INNER JOIN delete_accounts d ON f.context_type = 'Account' AND f.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_folders SELECT f.id FROM folders f INNER JOIN delete_courses d ON f.context_type = 'Course' AND f.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_folders SELECT f.id FROM folders f INNER JOIN delete_groups d ON f.context_type = 'Group' AND f.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_folders SELECT f.id FROM folders f INNER JOIN delete_users d ON f.context_type = 'User' AND f.context_id = d.id")

      # Create temporary table with all group category IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_group_categories (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_group_categories SELECT g.id FROM group_categories g INNER JOIN delete_accounts d ON g.context_type = 'Account' AND g.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_group_categories SELECT g.id FROM group_categories g INNER JOIN delete_courses d ON g.context_type = 'Course' AND g.context_id = d.id")

      # Create temporary table with all attachment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_attachments (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_accounts d ON a.context_type = 'Account' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_assessment_questions d ON a.context_type = 'AssessmentQuestion' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_assignments d ON a.context_type = 'Assignment' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_content_exports d ON a.context_type = 'ContentExport' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_content_migrations d ON a.context_type = 'ContentMigration' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_courses d ON a.context_type = 'Course' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_eportfolios d ON a.context_type = 'Eportfolio' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_folders d ON a.context_type = 'Folder' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_gradebook_uploads d ON a.context_type = 'GradebookUpload' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_groups d ON a.context_type = 'Group' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_sis_batches d ON a.context_type = 'SisBatch' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_quizzes d ON a.context_type = 'Quizzes::Quiz' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_quiz_statistics d ON a.context_type = 'Quizzes::QuizStatistics' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_quiz_submissions d ON a.context_type = 'Quizzes::QuizSubmission' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments SELECT a.id FROM attachments a INNER JOIN delete_users d ON a.context_type = 'User' AND a.context_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM delete_attachments WHERE id IN (SELECT m.attachment_id FROM content_migrations m LEFT OUTER JOIN delete_content_migrations d ON m.id = d.id WHERE d.id IS NULL)")
      ActiveRecord::Base.connection.execute("DELETE FROM delete_attachments WHERE id IN (SELECT root_attachment_id FROM attachments a LEFT OUTER JOIN delete_attachments d ON a.id = d.id WHERE d.id IS NULL)")
      ActiveRecord::Base.connection.execute("DELETE FROM delete_attachments WHERE id IN (SELECT replacement_attachment_id FROM attachments a LEFT OUTER JOIN delete_attachments d ON a.id = d.id WHERE d.id IS NULL)")

      # Create temporary table with all wiki IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_wikis (id BIGINT NOT NULL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_wikis SELECT w.id FROM wikis w INNER JOIN courses c ON c.wiki_id = w.id INNER JOIN delete_courses d ON c.id = d.id")
      ActiveRecord::Base.connection.execute("INSERT INTO delete_wikis SELECT w.id FROM wikis w INNER JOIN groups g ON g.wiki_id = w.id INNER JOIN delete_groups d ON g.id = d.id")

      # Create temporary table with all wiki page IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_wiki_pages (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_wiki_pages (
          SELECT p.id FROM wiki_pages p INNER JOIN delete_assignments d ON p.assignment_id = d.id
          UNION
          SELECT p.id FROM wiki_pages p INNER JOIN delete_assignments d ON p.old_assignment_id = d.id
          UNION
          SELECT p.id FROM wiki_pages p INNER JOIN delete_users d ON p.user_id = d.id
          UNION
          SELECT p.id FROM wiki_pages p INNER JOIN delete_wikis d ON p.wiki_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)

      # Create temporary table with all account notification IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_account_notifications (id BIGINT NOT NULL PRIMARY KEY)")
      sql = <<-SQL
        INSERT INTO delete_account_notifications (
          SELECT n.id FROM account_notifications n INNER JOIN delete_accounts d ON n.account_id = d.id
          UNION
          SELECT n.id FROM account_notifications n INNER JOIN delete_users d ON n.user_id = d.id
        )
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished preparing data in #{real_time.to_i} seconds."
  end

  def delete_in_postgres
    Rails.logger.info "[ACCOUNT-REMOVER] Deleting data in Postgres..."
    real_time = Benchmark.realtime do
      # LEVEL 0
      delete_access_tokens
      delete_account_notification_roles
      delete_account_users
      delete_account_programs
      delete_account_reports
      delete_alert_criteria
      delete_calendar_events
      delete_appointment_group_contexts
      delete_appointment_group_sub_contexts
      delete_appointment_groups
      delete_assessment_question_bank_users
      delete_assessment_question_banks
      delete_assessment_questions
      delete_assessment_requests
      delete_asset_user_accesses
      delete_assignment_groups
      delete_assignment_override_students
      delete_attachment_associations
      delete_cached_grade_distributions
      delete_canvadocs
      delete_canvadocs_submissions
      delete_collaborators
      delete_content_exports
      delete_content_participation_counts
      delete_content_participations
      delete_context_external_tool_placements
      delete_context_module_progressions
      delete_conversation_batches
      delete_conversation_message_participants
      delete_conversation_participants
      delete_course_account_associations
      delete_custom_gradebook_column_data
      delete_delayed_messages
      delete_delayed_notifications
      delete_developer_keys
      delete_discussion_entry_participants
      delete_discussion_topic_materialized_views
      delete_discussion_topic_participants
      delete_enrollment_states
      delete_enrollments
      delete_enrollment_dates_overrides
      delete_eportfolio_entries
      delete_error_reports
      delete_external_feed_entries
      delete_favorites
      delete_feature_flags
      delete_folders
      delete_gradebook_csvs
      delete_gradebook_uploads
      delete_grading_standards
      delete_group_memberships
      delete_ignores
      delete_learning_outcome_groups
      delete_learning_outcome_results
      delete_messages
      delete_migration_issues
      delete_oauth_requests
      delete_page_comments
      delete_page_views
      delete_page_views_rollups
      delete_profiles
      delete_quiz_groups
      delete_quiz_question_regrades
      delete_quiz_regrade_runs
      delete_quiz_statistics
      delete_quiz_submission_events
      delete_quiz_submission_snapshots
      delete_report_snapshots
      delete_role_overrides
      delete_rubric_assessments
      delete_session_persistence_tokens
      delete_stream_item_instances
      delete_stream_items
      delete_submission_comment_participants
      delete_submission_comments
      delete_submission_versions
      delete_thumbnails
      delete_user_account_associations
      delete_user_merge_data_records
      delete_user_notes
      delete_user_profile_links
      delete_user_services
      delete_versions
      delete_wiki_pages

      # LEVEL 1
      delete_account_notifications
      delete_alerts
      delete_assignment_overrides
      delete_collaborations
      delete_content_migrations
      delete_content_tags
      delete_context_external_tools
      delete_conversation_messages
      delete_custom_gradebook_columns
      delete_discussion_entries
      delete_eportfolio_categories
      delete_notification_policies
      delete_progresses
      delete_pseudonyms
      delete_quiz_questions
      delete_quiz_regrades
      delete_roles
      delete_rubric_associations
      delete_submissions
      delete_user_merge_data
      delete_user_profiles

      # LEVEL 2
      delete_account_authorization_configs
      delete_communication_channels
      delete_context_modules
      delete_conversations
      delete_discussion_topics
      delete_eportfolios
      delete_groups
      delete_learning_outcomes
      delete_quiz_submissions
      delete_rubrics

      # LEVEL 3
      delete_attachments
      delete_external_feeds
      delete_quizzes

      # LEVEL 4
      delete_assignments
      delete_usage_rights

      # LEVEL 5
      # delete_cloned_items
      delete_course_sections
      delete_group_categories

      # LEVEL 6
      delete_courses

      # LEVEL 7
      delete_enrollment_terms
      delete_wikis

      # LEVEL 8
      delete_accounts
      delete_sis_batches

      # LEVEL 9
      delete_users
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished deleting data in Postgres in #{real_time.to_i} seconds."
  end

  def delete_access_tokens
    timed_exec("DELETE FROM access_tokens USING delete_users d WHERE user_id = d.id")
  end

  def delete_account_authorization_configs
    timed_exec("DELETE FROM account_authorization_configs USING delete_accounts d WHERE account_id = d.id")
  end

  def delete_account_notification_roles
    timed_exec("DELETE FROM account_notification_roles USING delete_account_notifications d WHERE account_notification_id = d.id")
  end

  def delete_account_notifications
    timed_exec("DELETE FROM account_notifications USING delete_account_notifications d WHERE account_notifications.id = d.id")
  end

  def delete_account_programs
    timed_exec("DELETE FROM account_programs USING delete_accounts d WHERE account_id = d.id")
  end

  def delete_account_reports
    timed_exec("DELETE FROM account_reports USING delete_accounts d WHERE account_id = d.id")
  end

  def delete_account_users
    timed_exec("DELETE FROM account_users USING delete_accounts d WHERE account_id = d.id")
    timed_exec("DELETE FROM account_users USING delete_users d WHERE user_id = d.id")
  end

  def delete_accounts
    timed_exec("DELETE FROM accounts USING delete_accounts d WHERE accounts.id = d.id")
  end

  def delete_alert_criteria
    timed_exec("DELETE FROM alert_criteria USING delete_courses d, alerts a WHERE alert_id = a.id AND a.context_type = 'Course' AND a.context_id = d.id")
  end

  def delete_alerts
    timed_exec("DELETE FROM alerts USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_appointment_group_contexts
    timed_exec("DELETE FROM appointment_group_contexts USING delete_appointment_groups d WHERE appointment_group_id = d.id")
  end

  def delete_appointment_group_sub_contexts
    timed_exec("DELETE FROM appointment_group_sub_contexts USING delete_appointment_groups d WHERE appointment_group_id = d.id")
  end

  def delete_appointment_groups
    timed_exec("DELETE FROM appointment_groups USING delete_appointment_groups d WHERE appointment_groups.id = d.id")
  end

  def delete_assessment_question_bank_users
    timed_exec("DELETE FROM assessment_question_bank_users USING delete_assessment_question_banks d WHERE assessment_question_bank_id = d.id")
  end

  def delete_assessment_question_banks
    timed_exec("DELETE FROM assessment_question_banks USING delete_assessment_question_banks d WHERE assessment_question_banks.id = d.id")
  end

  def delete_assessment_questions
    timed_exec("DELETE FROM assessment_questions USING delete_assessment_questions d WHERE assessment_questions.id = d.id")
  end

  def delete_assessment_requests
    timed_exec("DELETE FROM assessment_requests USING delete_submissions d WHERE asset_type = 'Submission' AND asset_id = d.id")
  end

  def delete_asset_user_accesses
    timed_exec("DELETE FROM asset_user_accesses USING delete_users d WHERE user_id = d.id")
    timed_exec("DELETE FROM asset_user_accesses USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM asset_user_accesses USING delete_assessment_questions d WHERE context_type = 'AssessmentQuestion' and context_id = d.id")
    timed_exec("DELETE FROM asset_user_accesses USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
    timed_exec("DELETE FROM asset_user_accesses USING delete_groups d WHERE context_type = 'Group' AND context_id = d.id")
    timed_exec("DELETE FROM asset_user_accesses USING delete_users d WHERE context_type = 'User' and context_id = d.id")
  end

  def delete_assignment_groups
    timed_exec("DELETE FROM assignment_groups USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_assignment_override_students
    timed_exec("DELETE FROM assignment_override_students USING delete_assignment_overrides d WHERE assignment_override_id = d.id")
    timed_exec("DELETE FROM assignment_override_students USING delete_users d WHERE user_id = d.id")
  end

  def delete_assignment_overrides
    timed_exec("DELETE FROM assignment_overrides USING delete_assignment_overrides d WHERE assignment_overrides.id = d.id")
  end

  def delete_assignments
    timed_exec("DELETE FROM assignments USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_attachment_associations
    timed_exec("DELETE FROM attachment_associations USING delete_conversation_messages d WHERE context_type = 'ConversationMessage' AND context_id = d.id")
    timed_exec("DELETE FROM attachment_associations USING delete_submissions d WHERE context_type = 'Submission' AND context_id = d.id")
  end

  def delete_attachments
    timed_exec("DELETE FROM attachments USING delete_attachments d WHERE attachments.id = d.id")
  end

  def delete_cached_grade_distributions
    timed_exec("DELETE FROM cached_grade_distributions USING delete_courses d WHERE course_id = d.id")
  end

  def delete_calendar_events
    timed_exec("DELETE FROM calendar_events USING delete_calendar_events d WHERE calendar_events.id = d.id")
  end

  def delete_canvadocs
    timed_exec("DELETE FROM canvadocs USING delete_attachments d WHERE attachment_id = d.id")
  end

  def delete_canvadocs_submissions
    timed_exec("DELETE FROM canvadocs_submissions USING delete_submissions d WHERE submission_id = d.id")
  end

  def delete_collaborations
    timed_exec("DELETE FROM collaborations USING delete_collaborations d WHERE collaborations.id = d.id")
  end

  def delete_collaborators
    timed_exec("DELETE FROM collaborators USING delete_collaborations d WHERE collaboration_id = d.id")
    timed_exec("DELETE FROM collaborators USING delete_users d WHERE user_id = d.id")
  end

  def delete_communication_channels
    timed_exec("DELETE FROM communication_channels USING delete_users d WHERE user_id = d.id")
  end

  def delete_content_exports
    timed_exec("DELETE FROM content_exports USING delete_content_exports d WHERE content_exports.id = d.id")
  end

  def delete_content_migrations
    timed_exec("UPDATE content_exports SET content_migration_id = null FROM delete_content_migrations d WHERE content_exports.content_migration_id = d.id")
    timed_exec("DELETE FROM content_migrations USING delete_content_migrations d WHERE content_migrations.id = d.id")
  end

  def delete_content_participation_counts
    timed_exec("DELETE FROM content_participation_counts USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_content_participations
    timed_exec("DELETE FROM content_participations USING delete_submissions d WHERE content_type = 'Submission' AND content_id = d.id")
    timed_exec("DELETE FROM content_participations USING delete_users d WHERE user_id = d.id")
  end

  def delete_content_tags
    timed_exec("DELETE FROM content_tags USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM content_tags USING delete_assignments d WHERE context_type = 'Assignment' AND context_id = d.id")
    timed_exec("DELETE FROM content_tags USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_context_external_tool_placements
    timed_exec("DELETE FROM context_external_tool_placements USING delete_context_external_tools d WHERE context_external_tool_id = d.id")
  end

  def delete_context_external_tools
    timed_exec("DELETE FROM context_external_tools USING delete_context_external_tools d WHERE context_external_tools.id = d.id")
  end

  def delete_context_module_progressions
    timed_exec("DELETE FROM context_module_progressions USING delete_context_modules d WHERE context_module_id = d.id")
    timed_exec("DELETE FROM context_module_progressions USING delete_users d WHERE user_id = d.id")
  end

  def delete_context_modules
    timed_exec("DELETE FROM context_modules USING delete_context_modules d WHERE context_modules.id = d.id")
  end

  def delete_conversation_batches
    timed_exec("DELETE FROM conversation_batches USING delete_conversation_messages d WHERE root_conversation_message_id = d.id")
  end

  def delete_conversation_message_participants
    timed_exec("DELETE FROM conversation_message_participants USING delete_conversation_messages d WHERE conversation_message_id = d.id")
  end

  def delete_conversation_messages
    timed_exec("DELETE FROM conversation_messages USING delete_conversation_messages d WHERE conversation_messages.id = d.id")
  end

  def delete_conversation_participants
    timed_exec("DELETE FROM conversation_participants USING delete_conversations d WHERE conversation_id = d.id")
  end

  def delete_conversations
    timed_exec("DELETE FROM conversations USING delete_conversations d WHERE conversations.id = d.id")
  end

  def delete_course_account_associations
    timed_exec("DELETE FROM course_account_associations USING delete_courses d WHERE course_id = d.id")
    timed_exec("DELETE FROM course_account_associations USING course_sections s, delete_courses d WHERE course_section_id = s.id AND s.course_id = d.id")
  end

  def delete_course_sections
    timed_exec("DELETE FROM course_sections USING delete_courses d WHERE course_id = d.id")
  end

  def delete_courses
    timed_exec("DELETE FROM courses USING delete_courses d WHERE courses.id = d.id")
  end

  def delete_custom_gradebook_column_data
    timed_exec("DELETE FROM custom_gradebook_column_data USING custom_gradebook_columns c, delete_courses d WHERE c.course_id = d.id AND custom_gradebook_column_id = c.id")
  end

  def delete_custom_gradebook_columns
    timed_exec("DELETE FROM custom_gradebook_columns USING delete_courses d WHERE course_id = d.id")
  end

  def delete_delayed_messages
    timed_exec("DELETE FROM delayed_messages USING delete_users d, communication_channels c WHERE c.user_id = d.id AND communication_channel_id = c.id")
  end

  def delete_delayed_notifications
    timed_exec("DELETE FROM delayed_notifications USING delete_assignments d WHERE asset_type = 'Assignment' AND asset_id = d.id")
    timed_exec("DELETE FROM delayed_notifications USING delete_assignment_overrides d WHERE asset_type = 'AssignmentOverride' AND asset_id = d.id")
    timed_exec("DELETE FROM delayed_notifications USING delete_calendar_events d WHERE asset_type = 'CalendarEvent' AND asset_id = d.id")
    timed_exec("DELETE FROM delayed_notifications USING delete_discussion_topics d WHERE asset_type = 'DiscussionTopic' AND asset_id = d.id")
    timed_exec("DELETE FROM delayed_notifications USING delete_submissions d WHERE asset_type = 'Submission' AND asset_id = d.id")
    timed_exec("DELETE FROM delayed_notifications USING delete_quiz_submissions d WHERE asset_type = 'Quizzes::QuizSubmission' AND asset_id = d.id")
  end

  def delete_developer_keys
    sql = <<-SQL
      WITH delete_developer_keys AS (
        DELETE FROM developer_keys USING delete_accounts d WHERE account_id = d.id RETURNING developer_keys.id
      )
      DELETE FROM access_tokens USING delete_developer_keys d WHERE developer_key_id = d.id
    SQL
    timed_exec(sql)
  end

  def delete_discussion_entries
    timed_exec("UPDATE discussion_entries SET parent_id = null FROM delete_discussion_entries d WHERE parent_id = d.id")
    timed_exec("UPDATE discussion_entries SET root_entry_id = null FROM delete_discussion_entries d WHERE root_entry_id = d.id")
    timed_exec("DELETE FROM discussion_entries USING delete_discussion_entries d WHERE discussion_entries.id = d.id")
  end

  def delete_discussion_entry_participants
    timed_exec("DELETE FROM discussion_entry_participants USING delete_discussion_entries d WHERE discussion_entry_id = d.id")
    timed_exec("DELETE FROM discussion_entry_participants USING delete_users d WHERE user_id = d.id")
  end

  def delete_discussion_topic_materialized_views
    timed_exec("DELETE FROM discussion_topic_materialized_views USING delete_discussion_topics d WHERE discussion_topic_id = d.id")
  end

  def delete_discussion_topic_participants
    timed_exec("DELETE FROM discussion_topic_participants USING delete_discussion_topics d WHERE discussion_topic_id = d.id")
    timed_exec("DELETE FROM discussion_topic_participants USING delete_users d WHERE user_id = d.id")
  end

  def delete_discussion_topics
    timed_exec("DELETE FROM discussion_topics USING delete_discussion_topics d WHERE discussion_topics.id = d.id")
  end

  def delete_enrollment_dates_overrides
    timed_exec("DELETE FROM enrollment_dates_overrides USING enrollment_terms d WHERE d.root_account_id = #{@account.id} AND enrollment_term_id = d.id")
  end

  def delete_enrollment_states
    timed_exec("DELETE FROM enrollment_states USING delete_enrollments d WHERE enrollment_id = d.id")
  end

  def delete_enrollment_terms
    timed_exec("DELETE FROM enrollment_terms WHERE root_account_id = #{@account.id}")
  end

  def delete_enrollments
    timed_exec("DELETE FROM enrollments USING delete_enrollments d WHERE enrollments.id = d.id")
  end

  def delete_eportfolio_categories
    timed_exec("DELETE FROM eportfolio_categories USING delete_eportfolios d WHERE eportfolio_id = d.id")
  end

  def delete_eportfolio_entries
    timed_exec("DELETE FROM eportfolio_entries USING delete_eportfolios d WHERE eportfolio_id = d.id")
  end

  def delete_eportfolios
    timed_exec("DELETE FROM eportfolios USING delete_users d WHERE user_id = d.id")
  end

  def delete_error_reports
    timed_exec("DELETE FROM error_reports USING delete_accounts d WHERE account_id = d.id")
    timed_exec("DELETE FROM error_reports USING delete_users d WHERE user_id = d.id")
  end

  def delete_external_feed_entries
    timed_exec("DELETE FROM external_feed_entries USING delete_external_feeds d WHERE external_feed_id = d.id")
  end

  def delete_external_feeds
    timed_exec("DELETE FROM external_feeds USING delete_external_feeds d WHERE external_feeds.id = d.id")
  end

  def delete_favorites
    timed_exec("DELETE FROM favorites USING delete_users d WHERE user_id = d.id")
  end

  def delete_feature_flags
    timed_exec("DELETE FROM feature_flags USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM feature_flags USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
    timed_exec("DELETE FROM feature_flags USING delete_users d WHERE context_type = 'User' AND context_id = d.id")
  end

  def delete_folders
    timed_exec("DELETE FROM folders USING delete_folders d WHERE folders.id = d.id")
  end

  def delete_gradebook_csvs
    timed_exec("DELETE FROM gradebook_csvs USING delete_courses d WHERE course_id = d.id")
  end

  def delete_gradebook_uploads
    timed_exec("DELETE FROM gradebook_uploads USING delete_gradebook_uploads d WHERE gradebook_uploads.id = d.id")
  end

  def delete_grading_standards
    timed_exec("DELETE FROM grading_standards USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM grading_standards USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_group_categories
    timed_exec("DELETE FROM group_categories USING delete_group_categories d WHERE group_categories.id = d.id")
  end

  def delete_group_memberships
    timed_exec("DELETE FROM group_memberships USING delete_groups d WHERE group_id = d.id")
    timed_exec("DELETE FROM group_memberships USING delete_users d WHERE user_id = d.id")
  end

  def delete_groups
    timed_exec("DELETE FROM groups USING delete_groups d WHERE groups.id = d.id")
  end

  def delete_ignores
    timed_exec("DELETE FROM ignores USING delete_users d WHERE user_id = d.id")
  end

  def delete_learning_outcome_groups
    timed_exec("DELETE FROM learning_outcome_groups USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM learning_outcome_groups USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_learning_outcome_results
    timed_exec("DELETE FROM learning_outcome_results USING delete_learning_outcome_results d WHERE learning_outcome_results.id = d.id")
  end

  def delete_learning_outcomes
    timed_exec("DELETE FROM learning_outcomes USING delete_learning_outcomes d WHERE learning_outcomes.id = d.id")
  end

  def delete_messages
    if @truncate_messages
      # Create temporary table with all retained messages
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE keep_messages AS SELECT m.* FROM messages m LEFT OUTER JOIN delete_users d ON m.user_id = d.id WHERE d.id IS NULL AND m.root_account_id <> #{@account.id}")
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE messages")
      ActiveRecord::Base.connection.execute("INSERT INTO messages SELECT * FROM keep_messages")
      ActiveRecord::Base.connection.execute("DROP TABLE keep_messages")
    else
      timed_exec("DELETE FROM messages WHERE root_account_id = #{@account.id}")
      timed_exec("DELETE FROM messages USING delete_users d WHERE user_id = d.id")
    end
  end

  def delete_migration_issues
    timed_exec("DELETE FROM migration_issues USING delete_content_migrations d WHERE content_migration_id = d.id")
  end

  def delete_notification_policies
    timed_exec("DELETE FROM notification_policies USING delete_users d, communication_channels c WHERE c.user_id = d.id AND communication_channel_id = c.id")
  end

  def delete_oauth_requests
    timed_exec("DELETE FROM oauth_requests USING delete_users d WHERE user_id = d.id")
  end

  def delete_page_comments
    timed_exec("DELETE FROM page_comments USING delete_users d WHERE user_id = d.id")
  end

  def delete_page_views
    timed_exec("DELETE FROM page_views USING delete_accounts d WHERE account_id = d.id")
    timed_exec("DELETE FROM page_views USING delete_users d WHERE user_id = d.id")
  end

  def delete_page_views_rollups
    timed_exec("DELETE FROM page_views_rollups USING delete_courses d WHERE course_id = d.id")
  end

  def delete_profiles
    timed_exec("DELETE FROM profiles WHERE root_account_id = #{@account.id}")
  end

  def delete_progresses
    timed_exec("DELETE FROM progresses USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_attachments d WHERE context_type = 'Attachment' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_content_exports d WHERE context_type = 'ContentExport' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_content_migrations d WHERE context_type = 'ContentMigration' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_group_categories d WHERE context_type = 'GroupCategory' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_quiz_statistics d WHERE context_type = 'Quizzes::QuizStatistics' AND context_id = d.id")
    timed_exec("DELETE FROM progresses USING delete_users d WHERE context_type = 'User' AND context_id = d.id")
  end

  def delete_pseudonyms
    timed_exec("DELETE FROM pseudonyms USING delete_accounts d WHERE account_id = d.id")
  end

  def delete_quiz_groups
    timed_exec("DELETE FROM quiz_groups USING delete_quizzes d WHERE quiz_id = d.id")
  end

  def delete_quiz_question_regrades
    timed_exec("DELETE FROM quiz_question_regrades USING delete_quizzes d, quiz_regrades r WHERE r.quiz_id = d.id AND quiz_regrade_id = r.id")
  end

  def delete_quiz_questions
    timed_exec("DELETE FROM quiz_questions USING delete_quizzes d WHERE quiz_id = d.id")
  end

  def delete_quiz_regrade_runs
    timed_exec("DELETE FROM quiz_regrade_runs USING delete_quizzes d, quiz_regrades r WHERE r.quiz_id = d.id AND quiz_regrade_id = r.id")
  end

  def delete_quiz_regrades
    timed_exec("DELETE FROM quiz_regrades USING delete_quizzes d WHERE quiz_id = d.id")
  end

  def delete_quiz_statistics
    timed_exec("DELETE FROM quiz_statistics USING delete_quizzes d WHERE quiz_id = d.id")
  end

  def delete_quiz_submission_events
    timed_exec("DELETE FROM quiz_submission_events USING delete_quiz_submissions d WHERE quiz_submission_id = d.id")
  end

  def delete_quiz_submission_snapshots
    timed_exec("DELETE FROM quiz_submission_snapshots USING delete_quiz_submissions d WHERE quiz_submission_id = d.id")
  end

  def delete_quiz_submissions
    timed_exec("DELETE FROM quiz_submissions USING delete_quiz_submissions d WHERE quiz_submissions.id = d.id")
  end

  def delete_quizzes
    timed_exec("DELETE FROM quizzes USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_report_snapshots
    timed_exec("DELETE FROM report_snapshots USING delete_accounts d WHERE account_id = d.id")
  end

  def delete_role_overrides
    timed_exec("DELETE FROM role_overrides USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
    timed_exec("DELETE FROM role_overrides USING roles r WHERE role_id = r.id AND r.root_account_id = #{@account.id}")
  end

  def delete_roles
    timed_exec("DELETE FROM roles WHERE root_account_id = #{@account.id}")
  end

  def delete_rubric_assessments
    timed_exec("DELETE FROM rubric_assessments USING delete_rubric_assessments d WHERE rubric_assessments.id = d.id")
  end

  def delete_rubric_associations
    timed_exec("DELETE FROM rubric_associations USING delete_rubric_associations d WHERE rubric_associations.id = d.id")
  end

  def delete_rubrics
    timed_exec("DELETE FROM rubrics USING delete_rubrics d WHERE rubrics.id = d.id")
  end

  def delete_session_persistence_tokens
    timed_exec("DELETE FROM session_persistence_tokens USING delete_accounts d, pseudonyms p WHERE p.account_id = d.id AND pseudonym_id = p.id")
  end

  def delete_sis_batches
    timed_exec("DELETE FROM sis_batches USING delete_sis_batches d WHERE sis_batches.id = d.id")
  end

  def delete_stream_item_instances
    timed_exec("DELETE FROM stream_item_instances USING delete_stream_items d WHERE stream_item_id = d.id")
    timed_exec("DELETE FROM stream_item_instances USING delete_users d WHERE user_id = d.id")
  end

  def delete_stream_items
    timed_exec("DELETE FROM stream_items USING delete_stream_items d WHERE stream_items.id = d.id")
  end

  def delete_submission_comment_participants
    timed_exec("DELETE FROM submission_comment_participants USING delete_submission_comments d WHERE submission_comment_id = d.id")
    timed_exec("DELETE FROM submission_comment_participants USING delete_users d WHERE user_id = d.id")
  end

  def delete_submission_comments
    timed_exec("DELETE FROM submission_comments USING delete_submission_comments d WHERE submission_comments.id = d.id")
  end

  def delete_submission_versions
    timed_exec("DELETE FROM submission_versions USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_submissions
    timed_exec("DELETE FROM submissions USING delete_submissions d WHERE submissions.id = d.id")
  end

  def delete_thumbnails
    timed_exec("DELETE FROM thumbnails USING delete_attachments d WHERE parent_id = d.id")
  end

  def delete_usage_rights
    timed_exec("DELETE FROM usage_rights USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
  end

  def delete_user_account_associations
    timed_exec("DELETE FROM user_account_associations USING delete_accounts d WHERE account_id = d.id")
    timed_exec("DELETE FROM user_account_associations USING delete_users d WHERE user_id = d.id")
  end

  def delete_user_merge_data
    timed_exec("DELETE FROM user_merge_data USING delete_users d WHERE user_id = d.id")
  end

  def delete_user_merge_data_records
    timed_exec("DELETE FROM user_merge_data_records USING delete_users d, user_merge_data u WHERE user_merge_data_id = u.id AND u.user_id = d.id")
  end

  def delete_user_notes
    timed_exec("DELETE FROM user_notes USING delete_users d WHERE user_id = d.id")
    timed_exec("DELETE FROM user_notes USING delete_users d WHERE created_by_id = d.id")
  end

  def delete_user_profile_links
    timed_exec("DELETE FROM user_profile_links USING delete_users d, user_profiles p WHERE p.user_id = d.id AND user_profile_id = p.id")
  end

  def delete_user_profiles
    timed_exec("DELETE FROM user_profiles USING delete_users d WHERE user_id = d.id")
  end

  def delete_user_services
    timed_exec("DELETE FROM user_services USING delete_users d WHERE user_id = d.id")
  end

  def delete_users
    timed_exec("UPDATE content_exports SET user_id = null FROM delete_users d WHERE content_exports.user_id = d.id")
    timed_exec("UPDATE content_migrations SET user_id = null FROM delete_users d WHERE content_migrations.user_id = d.id")
    timed_exec("UPDATE discussion_entries SET editor_id = null FROM delete_users d WHERE discussion_entries.editor_id = d.id")
    timed_exec("UPDATE discussion_topics SET editor_id = null FROM delete_users d WHERE discussion_topics.editor_id = d.id")
    timed_exec("DELETE FROM users USING delete_users d WHERE users.id = d.id")
  end

  def delete_versions
    timed_exec("DELETE FROM versions USING delete_assignments d WHERE versionable_type = 'Assignment' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_assessment_questions d WHERE versionable_type = 'AssessmentQuestion' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_assignment_overrides d WHERE versionable_type = 'AssignmentOverride' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_learning_outcomes d WHERE versionable_type = 'LearningOutcome' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_learning_outcome_results d WHERE versionable_type = 'LearningOutcomeResult' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_quizzes d WHERE versionable_type = 'Quizzes::Quiz' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_quiz_submissions d WHERE versionable_type = 'Quizzes::QuizSubmission' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_rubrics d WHERE versionable_type = 'Rubric' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_rubric_assessments d WHERE versionable_type = 'RubricAssessment' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_submissions d WHERE versionable_type = 'Submission' AND versionable_id = d.id")
    timed_exec("DELETE FROM versions USING delete_wiki_pages d WHERE versionable_type = 'WikiPage' AND versionable_id = d.id")
  end

  def delete_wiki_pages
    timed_exec("DELETE FROM wiki_pages USING delete_wiki_pages d WHERE wiki_pages.id = d.id")
  end

  def delete_wikis
    timed_exec("DELETE FROM wikis USING delete_wikis d WHERE wikis.id = d.id")
  end

  # Deletes data related to the specified account from Cassandra
  def delete_account_from_cassandra(account_id)
    delete_page_views_main(account_id)
    delete_page_views_migration_metadata(account_id)
    delete_authentications(Switchman::Shard.global_id_for(account_id))
    delete_grade_changes(Switchman::Shard.global_id_for(account_id))
  end

  def delete_page_views_main(account_id)
    query = "SELECT request_id FROM page_views WHERE account_id = ? LIMIT 100 ALLOW FILTERING"
    loop do
      request_ids = []
      PageView::EventStream.database.execute(query, account_id).fetch {|row| request_ids << row["request_id"]}
      break if request_ids.empty?
      delete_page_views_history_by_context(request_ids)
      delete_participations_by_context(request_ids)
      PageView::EventStream.database.update("DELETE FROM page_views WHERE request_id IN (?)", request_ids)
    end
  end

  def delete_page_views_history_by_context(request_ids)
    query = "SELECT context_and_time_bucket FROM page_views_history_by_context WHERE request_id = ?"
    buckets = []
    request_ids.each do |request_id|
      PageView::EventStream.database.execute(query, request_id).fetch {|row| buckets << row["context_and_time_bucket"]}
    end
    buckets.uniq!
    PageView::EventStream.database.update("DELETE FROM page_views_history_by_context WHERE context_and_time_bucket IN (?)", buckets)
  end

  def delete_participations_by_context(request_ids)
    query = "SELECT context, created_at, request_id FROM participations_by_context WHERE request_id = ?"
    primary_keys = []
    request_ids.each do |request_id|
      PageView::EventStream.database.execute(query, request_id).fetch {|row| primary_keys << row.to_hash}
    end
    primary_keys.each do |keys|
      PageView::EventStream.database.update("DELETE FROM participations_by_context WHERE context = ? AND created_at = ? AND request_id = ?", keys["context"], keys["created_at"], keys["request_id"])
    end
  end

  def delete_page_views_migration_metadata(account_id)
    query = "SELECT shard_id, account_id FROM page_views_migration_metadata_per_account WHERE account_id = ? ALLOW FILTERING"
    primary_keys = []
    PageView::EventStream.database.execute(query, account_id).fetch {|row| primary_keys << row.to_hash}
    primary_keys.each do |keys|
      PageView::EventStream.database.update("DELETE FROM page_views_migration_metadata_per_account WHERE shard_id = ? AND account_id = ?", keys["shard_id"], keys["account_id"])
    end
  end

  def delete_authentications(account_global_id)
    query = "SELECT id FROM authentications WHERE account_id = ? LIMIT 100 ALLOW FILTERING"
    loop do
      ids = []
      Auditors::Authentication::Stream.database.execute(query, account_global_id).fetch {|row| ids << row["id"]}
      break if ids.empty?
      delete_authentications_index('authentications_by_account', ids)
      delete_authentications_index('authentications_by_user', ids)
      delete_authentications_index('authentications_by_pseudonym', ids)
      Auditors::Authentication::Stream.database.update("DELETE FROM authentications WHERE id IN (?)", ids)
    end
  end

  def delete_authentications_index(table_name, ids)
    delete_from_index(Auditors::Authentication::Stream.database, table_name, ids)
  end

  def delete_grade_changes(account_global_id)
    query = "SELECT id FROM grade_changes WHERE account_id = ? LIMIT 100 ALLOW FILTERING"
    loop do
      ids = []
      Auditors::GradeChange::Stream.database.execute(query, account_global_id).fetch {|row| ids << row["id"]}
      break if ids.empty?
      delete_grade_changes_index('grade_changes_by_root_account_grader', ids)
      delete_grade_changes_index('grade_changes_by_root_account_student', ids)
      delete_grade_changes_index('grade_changes_by_course', ids)
      delete_grade_changes_index('grade_changes_by_assignment', ids)
      Auditors::GradeChange::Stream.database.update("DELETE FROM grade_changes WHERE id IN (?)", ids)
    end
  end

  def delete_grade_changes_index(table_name, ids)
    delete_from_index(Auditors::GradeChange::Stream.database, table_name, ids)
  end

  # Deletes data related to the specified course from Cassandra
  def delete_course_from_cassandra(course_id)
    delete_auditors_courses(course_id)
  end

  def delete_auditors_courses(course_id)
    query = "SELECT id FROM courses WHERE course_id = ? LIMIT 100 ALLOW FILTERING"
    loop do
      ids = []
      Auditors::Course::Stream.database.execute(query, course_id).fetch {|row| ids << row.to_hash}
      break if ids.empty?
      delete_courses_index('courses_by_course', ids)
      Auditors::Course::Stream.database.update("DELETE FROM courses WHERE id IN (?)", ids)
    end
  end

  def delete_courses_index(table_name, ids)
    delete_from_index(Auditors::Course::Stream.database, table_name, ids)
  end

  # Deletes data related to the specified enrollment from Cassandra
  def delete_enrollment_from_cassandra(course_id, user_id)
    course_global_id = "course_#{Switchman::Shard.global_id_for(course_id)}"
    user_global_id = Switchman::Shard.global_id_for(user_id).to_s
    context = "#{course_global_id}/user_#{user_global_id}"
    PageView::EventStream.database.update("DELETE FROM page_views_counters_by_context_and_user WHERE context = ? AND user_id = ?", course_global_id, user_global_id)
    PageView::EventStream.database.update("DELETE FROM page_views_counters_by_context_and_hour WHERE context = ?", context)
    PageView::EventStream.database.update("DELETE FROM participations_by_context WHERE context = ?", context)
  end

  def delete_from_index(database, table_name, ids)
    query = "SELECT key, ordered_id FROM #{table_name} WHERE id = ? ALLOW FILTERING"
    keys = []
    ids.each do |id|
      database.execute(query, id).fetch {|row| keys << row.to_hash}
    end
    keys.each do |key|
      database.update("DELETE FROM #{table_name} WHERE key = ? AND ordered_id = ?", key["key"], key["ordered_id"])
    end
  end

  def cassandra?
    @cassandra_enabled ||= (Setting.get('enable_page_views', 'db') == 'cassandra')
    @cassandra_enabled && @include_cassandra
  end

  def postgres?
    @include_postgres
  end
end