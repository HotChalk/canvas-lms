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
        @parent_objects += Message.where(:root_account => account).to_a
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
      when Notification
        true
      when Pseudonym
        !@all_account_ids.include?(model.account_id)
      when Role
        model.built_in?
      when User
        !(model.pseudonyms.pluck(:account_id) - @all_account_ids).empty?
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
        AssetUserAccess.where(:context => model).delete_all
        RubricAssociation.where(:context => model).delete_all
        ContentTag.where(:context => model).delete_all
        Progress.where(:context => model).delete_all
        ActiveRecord::Base.connection.execute("DELETE FROM error_reports WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM account_authorization_configs WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM page_views WHERE account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM media_objects WHERE root_account_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM sis_batches WHERE account_id = #{model.id}")
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
        AssetUserAccess.where(:context => model).delete_all
        LearningOutcomeResult.where(:context => model).delete_all
        ContentTag.where(:context => model).delete_all
        RubricAssociation.where(:context => model).delete_all
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
        ActiveRecord::Base.connection.execute("UPDATE calendar_events SET course_section_id = null WHERE course_section_id = #{model.id}")
        ActiveRecord::Base.connection.execute("UPDATE groups SET course_section_id = null WHERE course_section_id = #{model.id}")
      when DiscussionEntry
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_entry_participants WHERE discussion_entry_id = #{model.id}")
      when DiscussionTopic
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_participants WHERE discussion_topic_id = #{model.id}")
        ActiveRecord::Base.connection.execute("DELETE FROM discussion_topic_materialized_views WHERE discussion_topic_id = #{model.id}")
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

  ASSOCIATION_EXCLUSIONS = {
    "Account" => [:sub_accounts, :all_accounts, :all_courses, :active_enrollment_terms, :active_assignments, :active_folders, :authentication_providers, :enrollments, :error_reports],
    "Announcement" => [:assignment_student_visibilities, :assignment_user_visibilities, :discussion_topic_user_visibilities, :active_assignment_overrides,
                       :rated_discussion_entries, :root_discussion_entries, :child_discussion_entries, :context_module_tags],
    "AssessmentQuestion" => [:versions, :current_version_unidirectional],
    "AssetUserAccess" => [:page_views],
    "Assignment" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional,
                     :active_assignment_overrides, :context_module_tags, :teacher_enrollment, :external_tool_tag, :learning_outcome_alignments, :rubric_association],
    "AssignmentGroup" => [:active_assignments, :published_assignments],
    "AssignmentOverride" => [:versions, :current_version_unidirectional],
    "Attachment" => [:context_module_tags, :account_report, :thumbnail, :attachment_associations, :canvadoc, :crocodoc_document, :media_object, :sis_batch, :submissions],
    "ContextModule" => [:content_tags],
    "Course" => [:asset_user_accesses, :page_views, :enrollments, :current_enrollments, :all_current_enrollments, :typical_current_enrollments, :prior_enrollments,
                 :student_enrollments, :admin_visible_student_enrollments, :all_student_enrollmens, :all_real_enrollments, :all_real_student_enrollments,
                 :teacher_enrollments, :ta_enrollments, :observer_enrollments, :instructor_enrollments, :admin_enrollments, :student_view_enrollments,
                 :active_announcements, :active_course_sections, :active_groups, :active_discussion_topics, :active_assignments, :active_images,
                 :active_folders, :active_quizzes, :active_context_modules, :content_participation_counts],
    "CourseSection" => [:assignment_overrides],
    "DelayedMessage" => [:notification, :context, :communication_channel],
    "DeveloperKey" => [:page_views],
    "DiscussionEntry" => [:discussion_entry_participants, :discussion_subentries, :flattened_discussion_subentries],
    "DiscussionTopic" => [:discussion_topic_user_visibilities, :discussion_topic_user_visibilities,
                          :discussion_topic_participants, :active_assignment_overrides, :rated_discussion_entries, :root_discussion_entries,
                          :child_discussion_entries, :context_module_tags],
    "Folder" => [:active_file_attachments, :file_attachments, :visible_file_attachments, :active_sub_folders, :sub_folders],
    "Group" => [:wiki_pages, :active_announcements, :discussion_topics, :active_discussion_topics, :active_assignments, :active_images, :active_folders],
    "LearningOutcomeQuestionResult" => [:versions, :current_version_unidirectional],
    "LearningOutcomeResult" => [:versions, :current_version_unidirectional],
    "Message" => [:notification, :asset_context, :communication_channel, :context, :root_account],
    "Quizzes::Quiz" => [:versions, :current_version_unidirectional, :active_assignment_overrides, :context_module_tags, :quiz_student_visibilities, :quiz_user_visibilities],
    "Quizzes::QuizSubmission" => [:events, :versions, :current_version_unidirectional],
    "Rubric" => [:versions, :current_version_unidirectional, :rubric_associations],
    "RubricAssessment" => [:versions, :current_version_unidirectional],
    "Submission" => [:versions, :current_version_unidirectional, :submission_comments, :visible_submission_comments, :hidden_submission_comments, :rubric_assessment],
    "User" => [:rubric_associations],
    "WikiPage" => [:assignment_student_visibilities, :assignment_user_visibilities, :versions, :current_version_unidirectional, :context_module_tags]
  }
end