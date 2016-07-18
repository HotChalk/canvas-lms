class SectionSplitter
  def self.run(opts)
    result = []
    user = opts[:user_id] && User.find(opts[:user_id])
    raise "User ID not provided or user not found" unless user
    if opts[:course_id]
      course = Course.find(opts[:course_id])
      raise "Course not found: #{opts[:course_id]}" unless course.present?
      result += self.process_course(user, course, opts)
    end
    if opts[:account_id]
      account = Account.find(opts[:account_id])
      raise "Account not found: #{opts[:account_id]}" unless account.present?
      account.all_courses.each do |course|
        result += self.process_course(user, course, opts)
      end
    end
    result
  end

  def self.process_course(user, course, opts)
    # Sanity check
    return unless course
    unless course.active_course_sections.length > 1
      Rails.logger.info "Skipping course #{course.id}: not a multi-section course"
      return
    end

    Rails.logger.info "Splitting course #{course.id} [#{course.name}]..."
    args = {
      :enrollment_term => course.enrollment_term,
      :abstract_course => course.abstract_course,
      :account => course.account
    }

    result = []
    course.active_course_sections.each do |source_section|
      target_course = self.perform_course_copy(user, course, source_section, args)
      self.perform_section_migration(target_course, source_section)
      result << target_course
    end
    result
  end

  def self.perform_course_copy(user, source_course, source_section, args)
    args[:name] = source_section.name
    args[:course_code] = source_section.name
    target_course = source_course.account.courses.new
    target_course.attributes = args
    target_course.workflow_state = source_course.workflow_state
    target_course.save!

    content_migration = target_course.content_migrations.build(:user => nil, :source_course => source_course, :context => target_course, :migration_type => 'course_copy_importer', :initiated_source => :manual)
    content_migration.migration_settings[:source_course_id] = source_course.id
    content_migration.workflow_state = 'created'

    content_migration.migration_settings[:import_immediately] = true
    content_migration.copy_options = {:everything => true}
    content_migration.migration_settings[:migration_ids_to_import] = {:copy => {:everything => true}}
    content_migration.user = user
    content_migration.save

    worker = Canvas::Migration::Worker::CourseCopyWorker.new
    begin
      worker.perform(content_migration)
    rescue Exception => e
      Canvas::Errors.capture_exception(:section_splitter, $ERROR_INFO)
      Rails.logger.error "Unable to perform course copy (content migration ID=#{content_migration.id}) for course ID=#{source_course.id} [#{source_course.name}]"
      raise e
    end

    target_course.reload
    target_course
  end

  def self.perform_section_migration(target_course, source_section)
    worker = SectionMigrationWorker.new(target_course.id, source_section.id)
    begin
      worker.perform
    rescue Exception => e
      Canvas::Errors.capture_exception(:section_splitter, $ERROR_INFO)
      Rails.logger.error "Unable to migrate source section ID=#{source_section.id} to target course ID=#{target_course.id}"
    end
  end

  SectionMigrationWorker = Struct.new(:target_course_id, :source_section_id) do
    def perform
      @target_course = Course.find(target_course_id)
      @source_section = CourseSection.find(source_section_id)
      @source_course = @source_section.course

      # Remove course content that is not available to the source section
      clean_assignments
      clean_quizzes
      clean_discussion_topics
      clean_announcements

      # Migrate user data
      migrate_section
      migrate_enrollments
      migrate_submissions
      migrate_quiz_submissions
      migrate_messages
      @target_course.save!
    end

    def clean_announcements
      clean_overridables(@target_course.announcements)
      @target_course.reload
    end

    def clean_assignments
      clean_overridables(@target_course.assignments)
      @target_course.reload
    end

    def clean_discussion_topics
      clean_overridables(@target_course.discussion_topics)
      @target_course.reload
    end

    def clean_quizzes
      clean_overridables(@target_course.quizzes)
      @target_course.reload
    end

    def clean_overridables(collection)
      to_remove = collection.map {|a| {:target => a, :source => source_model(@source_course, a)}}.select {|h| remove_based_on_overrides?(h[:source])}
      to_remove.each do |h|
        model = h[:target]
        if model.is_a?(DiscussionTopic)
          DiscussionTopic::MaterializedView.for(model).destroy
        elsif model.is_a?(Quizzes::Quiz) && model.assignment.present?
          @target_course.assignments.delete(model.assignment)
          model.assignment.assignment_overrides.each {|o| o.destroy_permanently!}
          model.assignment.destroy_permanently!
        elsif model.is_a?(Assignment) && model.quiz.present?
          @target_course.quizzes.delete(model.quiz)
          model.quiz.assignment_overrides.each {|o| o.destroy_permanently!}
          model.quiz.destroy_permanently!
        end
        collection.delete(model)
        model.assignment_overrides.each {|o| o.destroy_permanently!}
        model.destroy_permanently!
      end
    end

    def remove_based_on_overrides?(model)
      overrides = model.active_assignment_overrides.select {|ao| ao.set_type == 'CourseSection'}
      !overrides.empty? && !overrides.any? {|ao| ao.set_id == @source_section.id}
    end

    # Uses heuristics to locate the corresponding source content item in the source course for the given item in the target course.
    def source_model(source_course, model)
      source_model =
        case model
          when Announcement
            source_course.announcements.find {|a| a.workflow_state == model.workflow_state && a.title == model.title}
          when Assignment
            source_course.assignments.find {|a| a.workflow_state == model.workflow_state && a.title == model.title && a.points_possible == model.points_possible}
          when DiscussionTopic
            source_course.discussion_topics.find {|d| d.workflow_state == model.workflow_state && d.title == model.title}
          when Quizzes::Quiz
            source_course.quizzes.find {|q| q.workflow_state == model.workflow_state && q.title == model.title && q.points_possible == model.points_possible && q.question_count == model.question_count}
          else
            nil
        end
      raise "Unable to find source item for [#{model.inspect}] in course ID=#{source_course.id}" unless source_model
      source_model
    end

    def migrate_section
      @source_section.course = @target_course
      @source_section.save!
    end

    def migrate_enrollments
      @source_section.enrollments.each do |e|
        e.course = @target_course
        e.save!
      end
      @source_section.reload
      @target_course.reload
    end

    def migrate_submissions
      student_ids = @target_course.student_enrollments.map(&:user_id)
      @target_course.assignments.each do |a|
        source_assignment = source_model(@source_course, a)
        submissions = Submission.where(:assignment => source_assignment, :user_id => student_ids)
        submissions.update_all(:assignment_id => a.id)
        submission_comments = SubmissionComment.where(:submission_id => submissions.map(&:id), :context => @source_course)
        submission_comments.update_all(:context_id => @target_course.id)
      end
      @source_course.reload
      @target_course.reload
    end

    def migrate_quiz_submissions
      student_ids = @target_course.student_enrollments.map(&:user_id)
      @target_course.quizzes.each do |q|
        source_quiz = source_model(@source_course, q)
        submissions = Quizzes::QuizSubmission.where(:quiz => source_quiz, :user_id => student_ids)
        submissions.update_all(:quiz_id => q.id)
      end
      @source_course.reload
      @target_course.reload
    end

    def migrate_messages
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.messages.where(:user_id => user_ids).update_all(:context_id => @target_course.id)
      @source_course.reload
      @target_course.reload
    end
  end
end
