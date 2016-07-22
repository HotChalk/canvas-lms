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
      Rails.logger.info "[SECTION-SPLITTER] Skipping course #{course.id}: not a multi-section course"
      return
    end

    Rails.logger.info "[SECTION-SPLITTER] Splitting course #{course.id} [#{course.name}]..."
    result = []
    real_time = Benchmark.realtime do
      args = {
        :enrollment_term => course.enrollment_term,
        :abstract_course => course.abstract_course,
        :account => course.account,
        :start_at => course.start_at,
        :conclude_at => course.conclude_at,
        :time_zone => course.time_zone
      }

      course.active_course_sections.each do |source_section|
        target_course = self.perform_course_copy(user, course, source_section, args)
        self.perform_section_migration(target_course, source_section)
        Rails.logger.info "[SECTION-SPLITTER] Converted section #{source_section.id} [#{source_section.name}] into course #{target_course.id} [#{target_course.name}]"
        result << target_course
      end
    end
    Rails.logger.info "[SECTION-SPLITTER] Finished splitting course #{course.id} [#{course.name}] in #{real_time} seconds."
    if opts[:delete]
      Rails.logger.info "[SECTION-SPLITTER] Deleting course #{course.id} [#{course.name}]..."
      course.destroy
    end
    result
  end

  def self.perform_course_copy(user, source_course, source_section, args)
    args[:name] = source_course.name
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
      Rails.logger.error "[SECTION-SPLITTER] Unable to perform course copy (content migration ID=#{content_migration.id}) for course ID=#{source_course.id} [#{source_course.name}]"
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
      Rails.logger.error "[SECTION-SPLITTER] Unable to migrate source section ID=#{source_section.id} to target course ID=#{target_course.id}"
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
      clean_calendar_events

      # Migrate user data
      migrate_section
      migrate_enrollments
      migrate_overrides
      migrate_groups
      migrate_submissions
      migrate_quiz_submissions
      migrate_discussion_entries
      migrate_messages
      migrate_page_views
      migrate_asset_user_accesses
      migrate_content_participation_counts
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

    def clean_calendar_events
      @source_course.calendar_events.where("course_section_id IS NOT NULL AND course_section_id <> ?", @source_section.id).each do |source_event|
        target_event = source_model(@target_course, source_event)
        target_event.destroy_permanently!
      end
      @source_course.reload
      @target_course.reload
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
          when CalendarEvent
            source_course.calendar_events.find {|e| e.workflow_state == model.workflow_state && e.title == model.title && e.start_at == model.start_at && e.end_at == model.end_at }
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

    def migrate_overrides
      @target_course.assignments.active.each {|a| process_overrides(a)}
      @target_course.quizzes.active.each {|q| process_overrides(q)}
      @target_course.discussion_topics.active.each {|d| process_overrides(d)}
    end

    def process_overrides(model)
      source_model = source_model(@source_course, model)
      student_ids = @target_course.student_enrollments.map(&:user_id)
      source_model.active_assignment_overrides.each do |override|
        if (override.set_type == 'CourseSection' && override.set_id == @source_section.id) ||
          (override.set_type == 'ADHOC' && (override.assignment_override_students.map(&:user_id) - student_ids).empty?)
          clone_override(override, model)
        end
      end
    end

    def clone_override(override, new_model)
      return unless new_model.assignment_overrides.where(:set_type => override.set_type, :set_id => override.set_id).empty?
      new_override = override.clone
      case new_model
        when Assignment
          new_override.assignment = new_model
          new_override.save
          if new_override.set_type == 'ADHOC'
            override.assignment_override_students.each do |aos|
              new_aos = aos.clone
              new_aos.assignment = new_model
              new_override.assignment_override_students << new_aos
              new_override.save
            end
          end
        when Quizzes::Quiz
          new_override.quiz = new_model
          new_override.save
          if new_override.set_type == 'ADHOC'
            override.assignment_override_students.each do |aos|
              new_aos = aos.clone
              new_aos.quiz = new_model
              new_override.assignment_override_students << new_aos
              new_override.save
            end
          end
        when DiscussionTopic
          new_override.discussion_topic = new_model
          new_override.save
          if new_override.set_type == 'ADHOC'
            override.assignment_override_students.each do |aos|
              new_aos = aos.clone
              new_aos.discussion_topic = new_model
              new_override.assignment_override_students << new_aos
              new_override.save
            end
          end
        else
          raise "Unexpected model type in update_override: #{new_model.inspect}"
      end
      new_override.reload
    end

    def migrate_groups
      @source_course.groups.where(:course_section_id => @source_section.id).update_all(:context_id => @target_course.id)
      @source_course.reload
      @target_course.reload
    end

    def migrate_submissions
      student_ids = @target_course.student_enrollments.map(&:user_id)
      @target_course.assignments.each do |a|
        source_assignment = source_model(@source_course, a)
        submissions = Submission.where(:assignment => source_assignment, :user_id => student_ids)
        Submission.where(:assignment => a, :user_id => student_ids).delete_all
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

    def migrate_discussion_entries
      section_user_ids = @target_course.enrollments.map(&:user_id)
      @target_course.discussion_topics.each do |topic|
        source_topic = source_model(@source_course, topic)
        source_topic.discussion_entries.each do |entry|
          entry_ids = [entry.id] + entry.flattened_discussion_subentries.pluck(:id)
          participant_ids = [entry.user_id] + entry.flattened_discussion_subentries.pluck(:user_id)
          non_section_participant_ids = participant_ids - section_user_ids
          if non_section_participant_ids.empty?
            DiscussionEntry.where(:id => entry_ids).update_all(:discussion_topic_id => topic.id)
            DiscussionEntryParticipant.where("discussion_entry_id IN (?) AND user_id NOT IN (?)", entry_ids, section_user_ids).delete_all
          else
            Rails.logger.error "[SECTION-SPLITTER] Unable to migrate discussion entry #{entry.id}: contains mixed section subentries"
          end
        end
        source_topic.discussion_topic_participants.where(:user_id => section_user_ids).update_all(:discussion_topic_id => topic.id)
        source_topic.reload
        topic.reload
        topic.update_materialized_view
      end
    end

    def migrate_messages
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.messages.where(:user_id => user_ids).update_all(:context_id => @target_course.id)
      @source_course.reload
      @target_course.reload
    end

    def migrate_page_views
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.page_views.where(:user_id => user_ids).each do |p|
        p.context = @target_course
        p.save
      end
    end

    def migrate_asset_user_accesses
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.asset_user_accesses.where(:user_id => user_ids).update_all(:context_id => @target_course.id)
    end

    def migrate_content_participation_counts
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.content_participation_counts.where(:user_id => user_ids).update_all(:context_id => @target_course.id)
    end
  end
end
