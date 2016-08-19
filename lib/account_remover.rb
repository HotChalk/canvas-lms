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
    @account = opts[:account_id] && Account.find(opts[:account_id])
    raise "Account not found: #{opts[:account_id]}" unless @account.present?
    raise "Account is not a root account: #{opts[:account_id]}" unless @account.root_account?
    raise "Account is default root account or Site Admin: #{opts[:account_id]}" if Account.special_accounts.include?(@account)
  end

  def run
    @stack = []
    @parent_objects = []
    @association_benchmarks = {}
    @all_account_ids = (@account.all_accounts.pluck(:id) << @account.id)
    process_account(@account)
    Rails.logger.info "[ACCOUNT-REMOVER] FINAL PERFORMANCE MEASUREMENTS: #{@association_benchmarks.inspect}"
  end

  def process_account(account)
    Rails.logger.info "[ACCOUNT-REMOVER] Removing #{account.root_account? ? 'root ' : 'sub-'}account #{account.id} [#{account.name}]..."
    real_time = Benchmark.realtime do
      # Depth-first traversal of sub-accounts
      account.sub_accounts.each do |sub_account|
        process_account(sub_account)
      end

      # First soft-delete, then hard-delete the object graph starting from this account
      soft_delete(account)
      hard_delete(account)

      # Delete parts of the object graph that are not directly reachable by navigating relationships
      if account.root_account?
        until @parent_objects.empty?
          @parent_objects.map! {|object| object.reload rescue nil}.compact!
          @parent_objects.select! {|object| !recursive_delete(object)}
        end
      end
    end
    Rails.logger.info "[ACCOUNT-REMOVER] Finished removing #{account.root_account? ? 'root ' : 'sub-'}account #{account.id} [#{account.name}] in #{real_time} seconds."
  end

  def soft_delete(account)
    account.all_courses.destroy_all
    account.pseudonyms.select {|p| (p.user.pseudonyms.pluck(:account_id) - @all_account_ids).empty?}.each {|p| p.user.destroy}
    account.pseudonyms.destroy
    account.destroy
  end

  def hard_delete(account)
    while true
      break if recursive_delete(account)
    end
  end

  # Attempts to recursively delete the specified model instance.
  # Returns true if the deletion of the model itself, as well as its entire model sub-graph, was successful; false otherwise.
  def recursive_delete(model)
    key = model_key(model)
    return false if @stack.include?(key)
    return true if exclude?(model)
    Rails.logger.debug "[ACCOUNT-REMOVER] Visiting model: #{model_key(model)}..."
    @stack.push(key)

    # Prune selected sub-graphs (optimization)
    prune(model)

    # Walk through all child associations
    associations = model.class.reflect_on_all_associations(:has_many) + model.class.reflect_on_all_associations(:has_one)
    associations.reject! {|association| exclude_association?(model, association)}
    success = true
    associations.each do |association|
      Rails.logger.debug "[ACCOUNT-REMOVER] Traversing association: #{model.class.name}.#{association.name}"
      time = Benchmark.realtime do
        associated_objects = Array.wrap(model.send(association.name))
        associated_objects.each do |associated_object|
          success = (success && recursive_delete(associated_object))
        end
      end
      accumulated = @association_benchmarks["#{model.class.name}.#{association.name}"] || 0
      accumulated += time
      @association_benchmarks["#{model.class.name}.#{association.name}"] = accumulated
    end

    # Gather all parent associations
    parent_associations = model.class.reflect_on_all_associations(:belongs_to)
    parent_associations.reject! {|association| exclude_association?(model, association)}
    parent_associations.each do |parent_association|
      associated_objects = Array.wrap(model.send(parent_association.name))
      associated_objects.reject! {|object| @stack.include?(model_key(object))}
      @parent_objects += associated_objects
    end
    @parent_objects.uniq!

    @stack.pop
    if success
      success = delete(model)
    end
    success
  end

  def model_key(model)
    "#{model.class.name}_#{model.send(model.class.primary_key).to_s}"
  end

  # Returns true if the specified model object should not be deleted at all, false otherwise
  def exclude?(model)
    case model
      when Account
        !@all_account_ids.include?(model.id)
      when AccountUser
        !@all_account_ids.include?(model.account_id)
      when Attachment
        @all_account_ids.none? {|account_id| model.namespace.end_with?("account_#{account_id}")}
      when ClonedItem
        (model.original_item.present? && model.original_item.reload.present?) || !(model.attachments.empty? && model.discussion_topics.empty? && model.wiki_pages.empty?)
      when CourseAccountAssociation
        !@all_account_ids.include?(model.account_id)
      when DelayedMessage
        !@all_account_ids.include?(model.root_account_id)
      when Message
        !@all_account_ids.include?(model.root_account_id)
      when Notification
        true
      when Pseudonym
        !@all_account_ids.include?(model.account_id)
      when Role
        model.built_in? || !@all_account_ids.include?(model.account_id)
      when User
        !(model.pseudonyms.pluck(:account_id) - @all_account_ids).empty?
      when UserAccountAssociation
        !@all_account_ids.include?(model.account_id)
      else
        false
    end
  end

  # Returns true if the specified model object and association should be excluded from the object graph traversal, false otherwise
  def exclude_association?(model, association)
    (ASSOCIATION_EXCLUSIONS[model.class.name] || []).include?(association.name)
  end

  # Deletes the specified model object. Returns true if the deletion was successful, false otherwise.
  def delete(model)
    return true if model.new_record?
    begin
      model.reload
    rescue
      return true
    end
    result = true
    begin
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
        ActiveRecord::Base.connection.execute("DELETE FROM attachments WHERE id = #{model.id}")
      elsif model.is_a?(Thumbnail)
        ActiveRecord::Base.connection.execute("DELETE FROM thumbnails WHERE id = #{model.id}")
      elsif model.respond_to?(:destroy_permanently!)
        model.destroy_permanently!
      elsif model.respond_to?(:destroy)
        model.destroy
      else
        Rails.logger.error "[ACCOUNT-REMOVER] Don't know how to destroy model: #{model_key(model)}]"
        result = false
      end
      @parent_objects.delete(model)
      Rails.logger.info "[ACCOUNT-REMOVER] Deleted #{model_key(model)}"
    rescue Exception => e
      Rails.logger.warn "[ACCOUNT-REMOVER] Unable to destroy model: #{model_key(model)}]: #{e.inspect}"
      result = false
    end
    result
  end

  # Preemptively prunes some selected parts of the object graph. This is mainly a performance optimization that avoids
  # exploring high-cardinality associations that can be easily deleted.
  def prune(model)
    case model
      when Account
        delete_account_from_cassandra(model)
        AssetUserAccess.where(:context => model).delete_all
        ContentTag.where(:context => model).delete_all
        Progress.where(:context => model).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM error_reports WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM account_authorization_configs WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM page_views WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM media_objects WHERE root_account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM sis_batches WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM messages WHERE root_account_id = #{model.id}") if model.root_account?
        ActiveRecord::Base.connection.execute("DELETE FROM delayed_messages WHERE root_account_id = #{model.id}") if model.root_account?
      when AccountUser
        Message.where(:context => model).delete_all
        DelayedMessage.where(:context => model).delete_all
      when Announcement
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_participants WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_materialized_views WHERE discussion_topic_id = #{model.id}")
      when AssessmentQuestion
        Version.where(:versionable => model).delete_all
      when Assignment
        ActiveRecord::Base.connection.execute("UPDATE quizzes SET assignment_id = null WHERE assignment_id = #{model.id}")
        ContentTag.where(:context => model).delete_all
        ContentTag.where(:content => model).delete_all
        Progress.where(:context => model).delete_all
        Version.where(:versionable => model).delete_all
      when AssignmentOverride
        Version.where(:versionable => model).delete_all
      when Attachment
        Progress.where(:context => model).delete_all
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET attachment_id = null WHERE attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE content_exports SET attachment_id = null WHERE attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE content_migrations SET attachment_id = null WHERE attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE content_migrations SET overview_attachment_id = null WHERE overview_attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE content_migrations SET exported_attachment_id = null WHERE exported_attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM canvadocs WHERE attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM crocodoc_documents WHERE attachment_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM attachment_associations WHERE attachment_id = #{model.id}")
      when Course
        delete_course_from_cassandra(model)
        AssetUserAccess.where(:context => model).delete_all
        LearningOutcomeResult.where(:context => model).delete_all
        ContentTag.where(:context => model).delete_all
        SubmissionVersion.where(:context => model).delete_all
        wiki = model.wiki
        model.wiki = nil
        model.save!
        wiki.destroy
        Progress.where(:context => model).where("tag <> 'gradebook_to_csv'").delete_all
        ActiveRecord::Base.connection.execute("UPDATE content_migrations SET source_course_id = null WHERE source_course_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM cached_grade_distributions WHERE course_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM content_participation_counts WHERE context_type = 'Course' AND context_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM page_views_rollups WHERE course_id = #{model.id}")
      when CourseSection
        ActiveRecord::Base.connection.execute("UPDATE assignments SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE discussion_topics SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE calendar_events SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE groups SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE quizzes SET course_section_id = null WHERE course_section_id = #{model.id}")
      when DiscussionEntry
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entry_participants WHERE discussion_entry_id = #{model.id}")
      when DiscussionTopic
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_participants WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_materialized_views WHERE discussion_topic_id = #{model.id}")
      when Enrollment
        delete_enrollment_from_cassandra(model)
      when Group
        AssetUserAccess.where(:context => model).delete_all
        wiki = model.wiki
        model.wiki = nil
        model.save!
        wiki.destroy
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
        ContentTag.where(:context => model).delete_all
        Version.where(:versionable => model).delete_all
      when Quizzes::QuizSubmission
        Version.where(:versionable => model).delete_all
        Quizzes::QuizSubmissionSnapshot.where(:quiz_submission => model).delete_all
        ActiveRecord::Base.connection.execute("UPDATE submissions SET quiz_submission_id = null WHERE quiz_submission_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM quiz_submission_events WHERE quiz_submission_id = #{model.id}")
      when Rubric
        Version.where(:versionable => model).delete_all
      when RubricAssessment
        Version.where(:versionable => model).delete_all
      when Submission
        Version.where(:versionable => model).delete_all
      when WikiPage
        Version.where(:versionable => model).delete_all
      when User
        AccountNotification.where(:user => model).delete_all
        AssetUserAccess.where(:user => model).delete_all
        AssetUserAccess.where(:context => model).delete_all
        Progress.where(:context => model).delete_all
      else
        nil
    end
    unless model.new_record?
      model.reload rescue nil
    end
  end

  # Deletes data related to the specified account from Cassandra
  def delete_account_from_cassandra(account)
    return unless cassandra?
    delete_page_views(account.id)
    delete_page_views_migration_metadata(account.id)
    delete_authentications(account.global_id)
    delete_grade_changes(account.global_id)
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
  def delete_course_from_cassandra(course)
    return unless cassandra?
    delete_auditors_courses(course.id)
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
  def delete_enrollment_from_cassandra(enrollment)
    return unless cassandra?
    course_global_id = "course_#{enrollment.course.global_id}"
    user_global_id = enrollment.user.global_id.to_s
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
  end

  ASSOCIATION_EXCLUSIONS = {
    "Account" => [:sub_accounts, :all_accounts, :all_courses, :active_enrollment_terms, :active_assignments, :active_folders, :authentication_providers, :enrollments, :error_reports],
    "AccountNotificationRole" => [:role],
    "AccountUser" => [:account, :role],
    "Announcement" => [:assignment_student_visibilities, :assignment_user_visibilities, :discussion_topic_user_visibilities, :active_assignment_overrides,
                       :rated_discussion_entries, :root_discussion_entries, :child_discussion_entries, :context_module_tags],
    "AssessmentQuestion" => [:versions, :current_version_unidirectional],
    "AssetUserAccess" => [:page_views],
    "Assignment" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional,
                     :active_assignment_overrides, :context_module_tags, :teacher_enrollment, :external_tool_tag, :learning_outcome_alignments, :rubric_association],
    "AssignmentGroup" => [:active_assignments, :published_assignments],
    "AssignmentOverride" => [:versions, :current_version_unidirectional],
    "Attachment" => [:context_module_tags, :account_report, :thumbnail, :attachment_associations, :canvadoc, :crocodoc_document, :media_object,
                     :sis_batch, :submissions, :root_attachment, :replacement_attachment, :user, :context, :account, :assessment_question,
                     :assignment, :attachment, :content_export, :content_migration, :course, :eportfolio, :epub_export, :gradebook_upload,
                     :group, :submission, :context_folder, :context_sis_batch, :context_user, :quiz, :quiz_statistics, :quiz_submission],
    "AttachmentAssociation" => [:context, :conversation_message, :submission, :course, :group],
    "ClonedItem" => [:attachments, :discussion_topics, :wiki_pages, :original_item, :attachment, :content_tag, :folder, :assignment, :wiki_page,
                     :discussion_topic, :context_module, :calendar_event, :assignment_group, :context_external_tool, :quiz],
    "ContentExport" => [:context, :course, :group, :context_user],
    "ContentMigration" => [:context, :course, :account, :group, :context_user, :user, :source_course],
    "ContextModule" => [:content_tags, :context, :course],
    "Course" => [:asset_user_accesses, :page_views, :enrollments, :current_enrollments, :all_current_enrollments, :typical_current_enrollments, :prior_enrollments,
                 :student_enrollments, :admin_visible_student_enrollments, :all_student_enrollmens, :all_real_enrollments, :all_real_student_enrollments,
                 :teacher_enrollments, :ta_enrollments, :observer_enrollments, :instructor_enrollments, :admin_enrollments, :student_view_enrollments,
                 :active_announcements, :active_course_sections, :active_groups, :active_discussion_topics, :active_assignments, :active_images,
                 :active_folders, :active_quizzes, :active_context_modules, :content_participation_counts],
    "CourseAccountAssociation" => [:course, :course_section, :account, :account_users],
    "CourseSection" => [:assignment_overrides],
    "DelayedMessage" => [:notification, :notification_policy, :context, :communication_channel, :discussion_entry, :assignment, :submission_comment, :submission,
                         :conversation_message, :course, :discussion_topic, :enrollment, :attachment, :assignment_override, :group_membership,
                         :calendar_event, :wiki_page, :assessment_request, :account_user, :web_conference, :account, :user, :appointment_group,
                         :collaborator, :account_report, :alert, :context_communication_channel, :quiz_submission, :quiz_regrade_run],
    "DeveloperKey" => [:page_views],
    "DiscussionEntry" => [:discussion_entry_participants, :discussion_subentries, :flattened_discussion_subentries],
    "DiscussionTopic" => [:discussion_topic_user_visibilities, :discussion_topic_user_visibilities,
                          :discussion_topic_participants, :active_assignment_overrides, :rated_discussion_entries, :root_discussion_entries,
                          :child_discussion_entries, :context_module_tags],
    "EpubExport" => [:content_export, :course, :user],
    "Folder" => [:active_file_attachments, :file_attachments, :visible_file_attachments, :active_sub_folders, :sub_folders, :context, :user, :group, :account, :course],
    "Group" => [:wiki_pages, :active_announcements, :discussion_topics, :active_discussion_topics, :active_assignments, :active_images, :active_folders],
    "LearningOutcomeQuestionResult" => [:versions, :current_version_unidirectional],
    "LearningOutcomeResult" => [:versions, :current_version_unidirectional],
    "Message" => [:notification, :asset_context, :communication_channel, :context, :root_account, :user],
    "MigrationIssue" => [:error_report],
    "Progress" => [:context, :user, :content_migration, :course, :account, :group_category, :content_export, :assignment, :attachment, :epub_export, :context_user, :quiz_statistics],
    "Quizzes::Quiz" => [:versions, :current_version_unidirectional, :active_assignment_overrides, :context_module_tags, :quiz_student_visibilities, :quiz_user_visibilities],
    "Quizzes::QuizSubmission" => [:events, :versions, :current_version_unidirectional],
    "Rubric" => [:versions, :current_version_unidirectional, :user, :rubric, :context, :learning_outcome_alignments, :course, :account],
    "RubricAssessment" => [:versions, :current_version_unidirectional],
    "RubricAssociation" => [:rubric, :association_object, :context, :association_account, :association_course, :association_assignment, :course, :account],
    "Submission" => [:versions, :current_version_unidirectional, :submission_comments, :visible_submission_comments, :hidden_submission_comments, :rubric_assessment],
    "Thumbnail" => [:attachment],
    "User" => [:rubric_associations],
    "UserAccountAssociation" => [:user, :account],
    "WikiPage" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional, :context_module_tags]
  }
end