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
    raise "Must include at least one repository for data deletion: Postgres, Cassandra or both" unless @include_postgres || @include_cassandra
    raise "Cassandra is not enabled for this environment" if @include_cassandra && !cassandra?
    @account = opts[:account_id] && Account.find(opts[:account_id])
    raise "Account not found: #{opts[:account_id]}" unless @account.present?
    raise "Account is not a root account: #{opts[:account_id]}" unless @account.root_account?
    raise "Account is default root account or Site Admin: #{opts[:account_id]}" if Account.special_accounts.include?(@account)
  end

  def run
    begin
      @stack = []

      # Collect some convenient data points
      @all_account_ids = (@account.all_accounts.pluck(:id) << @account.id)
      @all_user_ids = Pseudonym.where(:account_id => @all_account_ids).pluck(:user_id).uniq - Pseudonym.where.not(:account_id => @all_account_ids).pluck(:user_id).uniq
      @all_course_ids = Course.where(:root_account_id => @account.id).pluck(:id)

      # Delete data from Cassandra and delete some simple, high-cardinality associations in Postgres
      preprocess_accounts
      preprocess_users
      preprocess_courses

      # Delete object graph in Postgres
      if postgres?
        process_account(@account)
        process_users
        process_miscellaneous
      end
    rescue Exception => e
      Rails.logger.error "[ACCOUNT-REMOVER] Account removal failed: #{e.inspect}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def preprocess_users
    if postgres?
      Rails.logger.info "[ACCOUNT-REMOVER] Pre-processing users in Postgres..."

      @account.transaction do
        # Create temporary table with all user IDs
        ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_users (id BIGINT NOT NULL PRIMARY KEY)")
        @all_user_ids.each_slice(100) do |batch_ids|
          ActiveRecord::Base.connection.execute("INSERT INTO delete_users (id) VALUES #{batch_ids.map {|id| "(#{id})"}.join(',')}")
        end

        # Delete by joining on the temp table
        c = ActiveRecord::Base.connection
        c.execute("DELETE FROM page_views USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM discussion_entry_participants USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM asset_user_accesses USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM asset_user_accesses USING delete_users d WHERE context_type = 'User' and context_id = d.id")
        c.execute("DELETE FROM messages USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM submission_comment_participants USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM conversation_message_participants USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM context_module_progressions USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM discussion_topic_participants USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM submission_versions USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM content_participations USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM content_participation_counts USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM stream_item_instances USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM group_memberships USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM delayed_messages USING delete_users d, communication_channels c WHERE c.user_id = d.id AND communication_channel_id = c.id")
        c.execute("DELETE FROM notification_policies USING delete_users d, communication_channels c WHERE c.user_id = d.id AND communication_channel_id = c.id")
        c.execute("DELETE FROM communication_channels USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM session_persistence_tokens USING delete_users d, pseudonyms p WHERE p.user_id = d.id AND pseudonym_id = p.id")
        c.execute("DELETE FROM pseudonyms USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM rubric_assessments USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM rubric_assessments USING delete_users d WHERE assessor_id = d.id")
        c.execute("DELETE FROM assessment_requests USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM assessment_requests USING delete_users d WHERE assessor_id = d.id")
        c.execute("DELETE FROM assignment_override_students USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM ignores USING delete_users d WHERE user_id = d.id")
        c.execute("DELETE FROM moderated_grading_selections USING delete_users d WHERE student_id = d.id")
      end
    end
  end

  def preprocess_accounts
    if cassandra?
      Rails.logger.info "[ACCOUNT-REMOVER] Pre-processing accounts in Cassandra..."
      @all_account_ids.each {|account_id| delete_account_from_cassandra(account_id)}
    end
    if postgres?
      Rails.logger.info "[ACCOUNT-REMOVER] Pre-processing accounts in Postgres..."

      @account.transaction do
        # Create temporary table with all account IDs
        ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_accounts (id BIGINT NOT NULL PRIMARY KEY)")
        ActiveRecord::Base.connection.execute("INSERT INTO delete_accounts (id) VALUES #{@all_account_ids.map {|id| "(#{id})"}.join(',')}")

        # Delete by joining on the temp table
        c = ActiveRecord::Base.connection
        c.execute("DELETE FROM page_views USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM asset_user_accesses USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
        c.execute("DELETE FROM error_reports USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM messages WHERE root_account_id = #{@account.id}")
        c.execute("DELETE FROM delayed_messages WHERE root_account_id = #{@account.id}")
        c.execute("DELETE FROM enrollments WHERE root_account_id = #{@account.id}")
        c.execute("DELETE FROM user_account_associations USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM course_account_associations USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM report_snapshots USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM role_overrides USING delete_accounts d WHERE context_type = 'Account' AND context_id = d.id")
        c.execute("DELETE FROM session_persistence_tokens USING delete_accounts d, pseudonyms p WHERE p.account_id = d.id AND pseudonym_id = p.id")
        c.execute("DELETE FROM pseudonyms USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM account_authorization_configs USING delete_accounts d WHERE account_id = d.id")
        c.execute("DELETE FROM conversation_batches USING conversation_messages c WHERE root_conversation_message_id = c.id AND c.context_type = 'Account' AND c.context_id = #{@account.id}")
        c.execute("DELETE FROM conversation_message_participants USING conversation_messages c WHERE conversation_message_id = c.id AND c.context_type = 'Account' AND c.context_id = #{@account.id}")
        c.execute("DELETE FROM conversation_messages WHERE context_type = 'Account' AND context_id = #{@account.id}")
        c.execute("DELETE FROM role_overrides USING roles r WHERE role_id = r.id AND r.root_account_id = #{@account.id}")
        c.execute("UPDATE accounts SET parent_account_id = root_account_id WHERE root_account_id <> #{@account.id} AND parent_account_id IN (SELECT id FROM delete_accounts)") # special case with old STU accounts
      end
    end
  end

  def preprocess_courses
    if cassandra?
      Rails.logger.info "[ACCOUNT-REMOVER] Pre-processing courses in Cassandra..."
      @all_course_ids.each do |course_id|
        delete_course_from_cassandra(course_id)
        user_ids = Enrollment.where(:course_id => course_id).pluck(:user_id).uniq
        user_ids.each {|user_id| delete_enrollment_from_cassandra(course_id, user_id)}
      end
    end
    if postgres?
      Rails.logger.info "[ACCOUNT-REMOVER] Pre-processing courses in Postgres..."

      @account.transaction do
        # Create temporary table with all course IDs
        ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_courses (id BIGINT NOT NULL PRIMARY KEY) ON COMMIT DROP")
        @all_course_ids.each_slice(100) do |batch_ids|
          ActiveRecord::Base.connection.execute("INSERT INTO delete_courses (id) VALUES #{batch_ids.map {|id| "(#{id})"}.join(',')}")
        end

        # Create temporary tables for rubrics
        ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_rubrics ON COMMIT DROP AS SELECT r.id FROM rubrics r INNER JOIN delete_courses c ON r.context_type = 'Course' AND r.context_id = c.id")
        ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_rubric_associations ON COMMIT DROP AS SELECT a.id FROM delete_rubrics r INNER JOIN rubric_associations a ON r.id = a.rubric_id")

        # Delete by joining on the temp table
        c = ActiveRecord::Base.connection
        c.execute("DELETE FROM versions USING delete_courses d, content_tags t WHERE t.context_type = 'Course' AND t.context_id = d.id AND versionable_type = t.content_type AND versionable_id = t.content_id")
        c.execute("DELETE FROM asset_user_accesses USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
        c.execute("DELETE FROM assessment_questions USING delete_courses d, assessment_question_banks b WHERE b.context_type = 'Course' AND b.context_id = d.id AND assessment_question_bank_id = b.id")
        c.execute("DELETE FROM assessment_question_banks USING delete_courses d WHERE context_type = 'Course' AND context_id = d.id")
        @all_course_ids.each_slice(100) do |batch_ids|
          section_ids = CourseSection.where(:course_id => batch_ids).pluck(:id)
          assignment_override_ids = AssignmentOverride.where(:set_type => 'CourseSection', :set_id => section_ids).pluck(:id)
          Version.where(:versionable_type => 'AssignmentOverride', :versionable_id => assignment_override_ids).delete_all
          AssignmentOverride.where(:id => assignment_override_ids).delete_all
        end
        c.execute("DELETE FROM cached_grade_distributions USING delete_courses d WHERE course_id = d.id")
        c.execute("DELETE FROM assessment_requests USING delete_rubric_associations d WHERE rubric_association_id = d.id")
        c.execute("DELETE FROM rubric_assessments USING delete_rubric_associations d WHERE rubric_association_id = d.id")
        c.execute("DELETE FROM rubric_assessments USING delete_rubrics d WHERE rubric_id = d.id")
        c.execute("DELETE FROM rubric_associations USING delete_rubric_associations d WHERE rubric_associations.id = d.id")
        c.execute("DELETE FROM versions USING delete_rubrics d WHERE versionable_type = 'Rubric' AND versionable_id = d.id")
        c.execute("DELETE FROM rubrics USING delete_rubrics d WHERE rubrics.id = d.id")
      end
    end
  end

  def process_account(account)
    Rails.logger.info "[ACCOUNT-REMOVER] Removing #{account.root_account? ? 'root ' : 'sub-'}account #{account.id} [#{account.name}]..."
    real_time = Benchmark.realtime do
      # Depth-first traversal of sub-accounts
      Account.where(:parent_account => account).each do |sub_account|
        process_account(sub_account)
      end
      recursive_delete(account)
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished removing #{account.root_account? ? 'root ' : 'sub-'}account #{account.id} [#{account.name}] in #{real_time} seconds."
  end

  def process_users
    Rails.logger.info "[ACCOUNT-REMOVER] Removing root account users..."
    real_time = Benchmark.realtime do
      ActiveRecord::Base.connection.execute("DELETE FROM attachments USING delete_users d WHERE context_type = 'User' AND context_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM folders USING delete_users d WHERE context_type = 'User' AND context_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM user_services USING delete_users d WHERE user_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM user_profiles USING delete_users d WHERE user_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM enrollments USING delete_users d WHERE user_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM user_account_associations USING delete_users d WHERE user_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM users USING delete_users d WHERE users.id = d.id")
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished removing root account users in #{real_time} seconds."
  end

  def process_miscellaneous
    Rails.logger.info "[ACCOUNT-REMOVER] Removing miscellaneous items..."
    real_time = Benchmark.realtime do
      # Create temporary table for all attachment IDs
      ActiveRecord::Base.connection.execute("CREATE TEMPORARY TABLE delete_attachments (id BIGINT NOT NULL PRIMARY KEY) ON COMMIT DROP")
      @attachment_ids.uniq! unless @attachment_ids.empty?
      @attachment_ids.each_slice(200) do |batch_ids|
        ActiveRecord::Base.connection.execute("INSERT INTO delete_attachments (id) VALUES #{batch_ids.map {|id| "(#{id})"}.join(',')}") unless @attachment_ids.empty?
      end

      ActiveRecord::Base.connection.execute("UPDATE attachments SET root_attachment_id = null FROM attachments a INNER JOIN delete_attachments d ON a.root_attachment_id = d.id")
      ActiveRecord::Base.connection.execute("UPDATE attachments SET replacement_attachment_id = null FROM attachments a INNER JOIN delete_attachments d ON a.replacement_attachment_id = d.id")
      ActiveRecord::Base.connection.execute("UPDATE content_migrations SET attachment_id = null FROM content_migrations c INNER JOIN delete_attachments d ON c.attachment_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM thumbnails USING delete_attachments d WHERE parent_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM canvadocs USING delete_attachments d WHERE attachment_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM crocodoc_documents USING delete_attachments d WHERE attachment_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM attachment_associations USING delete_attachments d WHERE attachment_id = d.id")
      ActiveRecord::Base.connection.execute("DELETE FROM attachments USING delete_attachments d WHERE attachments.id = d.id")
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished removing miscellaneous items in #{real_time} seconds."
  end

  def model_key(model)
    "#{model.class.name}_#{model.send(model.class.primary_key).to_s}"
  end

  # Attempts to recursively delete the specified model instance.
  # Returns true if the deletion of the model itself, as well as its entire model sub-graph, was successful; false otherwise.
  def recursive_delete(model)
    if can_delete?(model)
      Rails.logger.debug "[ACCOUNT-REMOVER] Visiting model: #{model_key(model)}..."

      # Run pre-delete actions
      before_delete(model)

      # Walk through all child associations
      associations = model.class.reflect_on_all_associations(:has_many) + model.class.reflect_on_all_associations(:has_one)
      associations.reject! {|association| exclude_association?(model, association)}
      associations.each do |association|
        Rails.logger.debug "[ACCOUNT-REMOVER] Traversing association: #{model.class.name}.#{association.name}"
        association_instance = model.send(association.name)
        associated_objects = Array.wrap(association_instance)
        associated_objects.each do |associated_object|
          recursive_delete(associated_object)
        end
      end

      # Delete the object
      delete(model)

      # Run post-delete actions
      after_delete(model)
    end
  end

  # Returns true if the specified model object should not be deleted at all, false otherwise
  def can_delete?(model)
    return false if @stack.include?(model)

    case model
      when Account
        @all_account_ids.include?(model.id)
      when AccountUser
        @all_account_ids.include?(model.account_id)
      when ClonedItem
        model.original_item.nil? && model.attachments.empty? && model.discussion_topics.empty? && model.wiki_pages.empty?
      when Notification
        false
      when Role
        !model.built_in? && @all_account_ids.include?(model.account_id)
      when User
        @all_user_ids.include?(model.id)
      else
        true
    end
  end

  # Returns true if the specified model object and association should be excluded from the object graph traversal, false otherwise
  def exclude_association?(model, association)
    (ASSOCIATION_EXCLUSIONS[model.class.name] || []).include?(association.name) || association.is_a?(ActiveRecord::Reflection::ThroughReflection)
  end

  # Deletes the specified model object. Returns true if the deletion was successful, false otherwise.
  def delete(model)
    return if model.new_record?
    model.reload rescue nil
    model.skip_broadcasts = true if model.respond_to?(:skip_broadcasts=)

    if model.is_a?(Folder)
      query = <<-SQL
        WITH RECURSIVE folders_tree (id, parent_folder_id, root_folder_id) AS (
          SELECT id, parent_folder_id, id as root_folder_id FROM folders WHERE id = #{model.id}
          UNION ALL
          SELECT f.id, f.parent_folder_id, ft.id FROM folders f, folders_tree ft WHERE f.parent_folder_id = ft.id
        ) DELETE FROM folders WHERE id IN (SELECT id FROM folders_tree);
      SQL
      ActiveRecord::Base.connection.execute(query)
    elsif model.is_a?(Attachment)
      mark_attachment(model.id)
    elsif model.is_a?(Thumbnail)
      # do nothing
    elsif model.respond_to?(:delete)
      model.delete
    elsif model.respond_to?(:destroy_permanently!)
      model.destroy_permanently!
    elsif model.respond_to?(:destroy)
      model.destroy
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Deleted #{model_key(model)}"
  end

  # Performs some pre-delete actions, such as preemptively pruning some selected parts of the object graph.
  # This is mainly a performance optimization that avoids exploring high-cardinality associations that can be easily deleted.
  def before_delete(model)
    @stack.push(model)

    case model
      when Account
        AccountNotification.where(:account => model).each {|notification| recursive_delete(notification)}
        ActiveRecord::Base.connection.execute("UPDATE groups SET account_id = #{@account.id} WHERE account_id = #{model.id}")
        Folder.where(:context => model).each {|folder| recursive_delete(folder)}
        ActiveRecord::Base.connection.execute("DELETE FROM stream_item_instances USING stream_items s WHERE stream_item_id = s.id AND s.context_type = 'Account' AND s.context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM stream_items WHERE context_type = 'Account' AND context_id = #{model.id}")
      when Announcement
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET root_topic_id = null WHERE root_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_participants WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_materialized_views WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entry_participants USING discussion_entries d WHERE d.discussion_topic_id = #{model.id} AND discussion_entry_participants.discussion_entry_id = d.id")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entries WHERE discussion_topic_id = #{model.id}")
      when AssessmentQuestion
        Version.where(:versionable => model).delete_all
      when Assignment
        ActiveRecord::Base.connection.execute("UPDATE quizzes SET assignment_id = null WHERE assignment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET reply_assignment_id = null WHERE reply_assignment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET old_assignment_id = null WHERE old_assignment_id = #{model.id}")
        ContentTag.where(:context => model).delete_all
        ContentTag.where(:content => model).delete_all
        Progress.where(:context => model).delete_all
        Version.where(:versionable => model).delete_all
      when AssignmentOverride
        Version.where(:versionable => model).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM stream_item_instances USING stream_items s WHERE stream_item_id = s.id AND s.context_type = 'AssignmentOverride' AND s.context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM stream_items WHERE context_type = 'AssignmentOverride' AND context_id = #{model.id}")
      when ContentExport
        Attachment.where(:context => model).each {|attachment| recursive_delete(attachment)}
      when ContentMigration
        Attachment.where(:context => model).each {|attachment| recursive_delete(attachment)}
      when Course
        Attachment.where(:context => model).each {|attachment| recursive_delete(attachment)}
        Folder.where(:context => model).each {|folder| recursive_delete(folder)}
        LearningOutcomeResult.where(:context => model).delete_all
        ContentTag.where(:context => model).delete_all
        SubmissionVersion.where(:context => model).delete_all
        wiki = model.wiki
        ActiveRecord::Base.connection.execute("UPDATE courses SET wiki_id = null WHERE id = #{model.id}")
        wiki.destroy
        Progress.where(:context => model).where("tag <> 'gradebook_to_csv'").delete_all
        ActiveRecord::Base.connection.execute("UPDATE content_migrations SET source_course_id = null WHERE source_course_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM cached_grade_distributions WHERE course_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM content_participation_counts WHERE context_type = 'Course' AND context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM page_views_rollups WHERE course_id = #{model.id}")
        rubric_ids = Rubric.where(:context => model).pluck(:id)
        rubric_association_ids = RubricAssociation.where(:rubric_id => rubric_ids)
        AssessmentRequest.where(:rubric_association_id => rubric_association_ids).delete_all
        RubricAssessment.where(:rubric_association_id => rubric_association_ids).delete_all
        RubricAssociation.where(:id => rubric_association_ids).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM stream_item_instances USING stream_items s WHERE stream_item_id = s.id AND s.context_type = 'Course' AND s.context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM stream_items WHERE context_type = 'Course' AND context_id = #{model.id}")
      when CourseSection
        AssignmentOverride.where(:set => model).delete_all
        ActiveRecord::Base.connection.execute("UPDATE assignments SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE calendar_events SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE groups SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE quizzes SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE course_account_associations SET course_section_id = null WHERE course_section_id = #{model.id}")
      when DiscussionTopic
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET root_topic_id = null WHERE root_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_participants WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_materialized_views WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entry_participants USING discussion_entries d WHERE d.discussion_topic_id = #{model.id} AND discussion_entry_participants.discussion_entry_id = d.id")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entries WHERE discussion_topic_id = #{model.id}")
      when Group
        Folder.where(:context => model).each {|folder| recursive_delete(folder)}
        Submission.where(:group => model).each {|submission| recursive_delete(submission)}
        GroupMembership.where(:group => model).each {|membership| recursive_delete(membership)}
        wiki = model.wiki
        ActiveRecord::Base.connection.execute("UPDATE groups SET wiki_id = null WHERE id = #{model.id}")
        wiki.destroy
        AssetUserAccess.where(:context => model).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM stream_item_instances USING stream_items s WHERE stream_item_id = s.id AND s.context_type = 'Group' AND s.context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM stream_items WHERE context_type = 'Group' AND context_id = #{model.id}")
      when LearningOutcomeGroup
        ContentTag.where(:context => model).delete_all
      when LearningOutcomeQuestionResult
        Version.where(:versionable => model).delete_all
      when LearningOutcomeResult
        Version.where(:versionable => model).delete_all
      when Progress
        GradebookCsv.where(:progress => model).delete_all
        GradebookUpload.where(:progress => model).delete_all
      when Quizzes::Quiz
        quiz_regrade_ids = Quizzes::QuizRegrade.where(:quiz => model).pluck(:id)
        Quizzes::QuizQuestionRegrade.where(:quiz_regrade_id => quiz_regrade_ids).delete_all
        Quizzes::QuizRegradeRun.where(:quiz_regrade_id => quiz_regrade_ids).delete_all
        Quizzes::QuizRegrade.where(:id => quiz_regrade_ids).delete_all
        Quizzes::QuizQuestion.where(:quiz => model).delete_all
        ContentTag.where(:context => model).delete_all
        Version.where(:versionable => model).delete_all
      when Quizzes::QuizStatistics
        Attachment.where(:context => model).each {|attachment| recursive_delete(attachment)}
      when Quizzes::QuizSubmission
        Version.where(:versionable => model).delete_all
        Quizzes::QuizSubmissionSnapshot.where(:quiz_submission => model).delete_all
        ActiveRecord::Base.connection.execute("UPDATE submissions SET quiz_submission_id = null WHERE quiz_submission_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM quiz_submission_events WHERE quiz_submission_id = #{model.id}")
      when Rubric
        ActiveRecord::Base.connection.execute("UPDATE rubrics SET rubric_id = null WHERE rubric_id = #{model.id}")
        Version.where(:versionable => model).delete_all
      when RubricAssessment
        Version.where(:versionable => model).delete_all
      when Submission
        Version.where(:versionable => model).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM canvadocs_submissions WHERE submission_id = #{model.id}")
        submission_comment_ids = SubmissionComment.where(:submission => model).pluck(:id)
        SubmissionCommentParticipant.where(:submission_comment_id => submission_comment_ids).delete_all
        SubmissionComment.where(:submission => model).delete_all
        AssessmentRequest.where(:asset => model).delete_all
        AssessmentRequest.where(:assessor_asset => model).delete_all
      when WikiPage
        Version.where(:versionable => model).delete_all
      when UsageRights
        ActiveRecord::Base.connection.execute("UPDATE attachments SET usage_rights_id = null WHERE usage_rights_id = #{model.id}")
      when User
        AccountNotification.where(:user => model).delete_all
        Progress.where(:context => model).delete_all
      else
        nil
    end
    unless model.new_record?
      model.reload rescue nil
    end
  end

  # Performs after-delete actions
  def after_delete(model)
    @stack.delete(model)
  end

  # Marks an attachment for deletion
  def mark_attachment(attachment_id)
    (@attachment_ids ||= []) << attachment_id
  end

  # Deletes data related to the specified account from Cassandra
  def delete_account_from_cassandra(account_id)
    return unless cassandra?
    delete_page_views(account_id)
    delete_page_views_migration_metadata(account_id)
    delete_authentications(Switchman::Shard.global_id_for(account_id))
    delete_grade_changes(Switchman::Shard.global_id_for(account_id))
  end

  def delete_page_views(account_id)
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
    return unless cassandra?
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
    return unless cassandra?
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

  ASSOCIATION_EXCLUSIONS = {
    "Account" => [:sub_accounts, :all_accounts, :all_courses, :active_enrollment_terms, :active_assignments, :active_folders, :authentication_providers, :enrollments, :all_enrollments, :error_reports,
                  :group_categories],
    "AccountNotificationRole" => [:role],
    "AccountUser" => [:account, :role],
    "Announcement" => [:assignment_student_visibilities, :assignment_user_visibilities, :discussion_topic_user_visibilities, :discussion_topic_participants, :active_assignment_overrides,
                       :discussion_entries, :rated_discussion_entries, :root_discussion_entries, :child_discussion_entries, :context_module_tags, :assignment_override_students,
                       :external_feed_entry, :child_topics, :stream_item],
    "AssessmentQuestion" => [:versions, :current_version_unidirectional],
    "AssetUserAccess" => [:page_views],
    "Assignment" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional,
                     :active_assignment_overrides, :context_module_tags, :teacher_enrollment, :external_tool_tag, :learning_outcome_alignments, :rubric_association,
                     :assignment_override_students, :ignores, :moderated_grading_selections, :rubric],
    "AssignmentGroup" => [:active_assignments, :published_assignments],
    "AssignmentOverride" => [:versions, :current_version_unidirectional],
    "Attachment" => [:context_module_tags, :account_report, :thumbnail, :thumbnails, :attachment_associations, :canvadoc, :crocodoc_document, :media_object,
                     :sis_batch, :submissions, :children],
    "ClonedItem" => [:attachments, :discussion_topics, :wiki_pages, :original_item, :attachment, :content_tag, :folder, :assignment, :wiki_page,
                     :discussion_topic, :context_module, :calendar_event, :assignment_group, :context_external_tool, :quiz],
    "ContentExport" => [:context, :course, :group, :context_user],
    "ContentMigration" => [:context, :course, :account, :group, :context_user, :user, :source_course],
    "ContextModule" => [:content_tags, :context, :course],
    "ConversationMessage" => [:attachment_associations, :stream_item],
    "Course" => [:asset_user_accesses, :page_views, :enrollments, :all_enrollments, :current_enrollments, :all_current_enrollments, :typical_current_enrollments, :prior_enrollments,
                 :student_enrollments, :admin_visible_student_enrollments, :all_student_enrollments, :all_real_enrollments, :all_real_student_enrollments,
                 :teacher_enrollments, :ta_enrollments, :observer_enrollments, :instructor_enrollments, :admin_enrollments, :student_view_enrollments,
                 :active_announcements, :active_course_sections, :active_groups, :active_discussion_topics, :active_assignments, :active_images,
                 :active_folders, :active_quizzes, :active_context_modules, :content_participation_counts],
    "CourseAccountAssociation" => [:course, :course_section, :account, :account_users],
    "CourseSection" => [:assignment_overrides, :enrollments, :all_enrollments, :student_enrollments, :all_student_enrollments, :instructor_enrollments, :admin_enrollments],
    "DelayedMessage" => [:notification, :notification_policy, :context, :communication_channel, :discussion_entry, :assignment, :submission_comment, :submission,
                         :conversation_message, :course, :discussion_topic, :enrollment, :attachment, :assignment_override, :group_membership,
                         :calendar_event, :wiki_page, :assessment_request, :account_user, :web_conference, :account, :user, :appointment_group,
                         :collaborator, :account_report, :alert, :context_communication_channel, :quiz_submission, :quiz_regrade_run],
    "DeveloperKey" => [:page_views],
    "DiscussionTopic" => [:discussion_topic_user_visibilities, :discussion_topic_user_visibilities,
                          :discussion_topic_participants, :active_assignment_overrides, :discussion_entries, :rated_discussion_entries, :root_discussion_entries,
                          :child_discussion_entries, :context_module_tags, :assignment_override_students, :assignment_student_visibilities, :assignment_user_visibilities,
                          :external_feed_entry, :child_topics, :stream_item],
    "EpubExport" => [:content_export, :course, :user],
    "Folder" => [:active_file_attachments, :file_attachments, :visible_file_attachments, :active_sub_folders, :sub_folders, :context, :user, :group, :account, :course],
    "Group" => [:wiki_pages, :active_announcements, :discussion_topics, :active_discussion_topics, :active_assignments, :active_images, :active_folders],
    "LearningOutcomeQuestionResult" => [:versions, :current_version_unidirectional],
    "LearningOutcomeResult" => [:versions, :current_version_unidirectional],
    "Message" => [:notification, :asset_context, :communication_channel, :context, :root_account, :user, :stream_item],
    "MigrationIssue" => [:error_report],
    "Progress" => [:context, :user, :content_migration, :course, :account, :group_category, :content_export, :assignment, :attachment, :epub_export, :context_user, :quiz_statistics],
    "Quizzes::Quiz" => [:versions, :current_version_unidirectional, :active_assignment_overrides, :context_module_tags, :quiz_student_visibilities, :quiz_user_visibilities, :assignment_override_students],
    "Quizzes::QuizSubmission" => [:events, :versions, :current_version_unidirectional, :enrollments],
    "Rubric" => [:versions, :current_version_unidirectional, :user, :rubric, :context, :learning_outcome_alignments, :course, :account],
    "RubricAssessment" => [:versions, :current_version_unidirectional],
    "RubricAssociation" => [:rubric, :association_object, :context, :association_account, :association_course, :association_assignment, :course, :account],
    "StudentEnrollment" => [:role_overrides, :pseudonyms, :course_account_associations],
    "Submission" => [:versions, :current_version_unidirectional, :submission_comments, :all_submission_comments, :visible_submission_comments, :hidden_submission_comments,
                     :rubric_assessment, :content_participations, :attachment_associations, :conversation_messages, :provisional_grades, :rubric_assessments, :stream_item,
                     :assessment_requests, :assigned_assessments],
    "TaEnrollment" => [:role_overrides, :pseudonyms, :course_account_associations],
    "TeacherEnrollment" => [:role_overrides, :pseudonyms, :course_account_associations],
    "Thumbnail" => [:attachment],
    "User" => [:rubric_associations, :assignment_student_visibilities, :assignment_user_visibilities, :discussion_topic_user_visibilities],
    "UserAccountAssociation" => [:user, :account],
    "WikiPage" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional, :context_module_tags]
  }
end