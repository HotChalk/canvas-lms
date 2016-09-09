#
# If your target environment is configured to use an Apache Cassandra cluster,
# please keep in mind that you will need to perform some configuration changes prior
# to running this tool:
#
# 1. Edit your cassandra.yml configuration file and set a high timeout value for each keyspace, e.g.:
#    timeout: 100000
#
# 2. Create the following indexes in your Cassandra cluster:
#    CREATE INDEX page_views_context_id_idx ON page_views.page_views (context_id);
#    CREATE INDEX grade_changes_context_id_idx ON auditors.grade_changes (context_id);
#
# 3. Update timeout settings in your server's cassandra.yaml configuration files to large values, i.e.:
#
#    read_request_timeout_in_ms: 60000
#    range_request_timeout_in_ms: 60000
#    request_timeout_in_ms: 60000
#
# Index creation can be a long-running process, so you should verify that the indexes have
# been successfully created by querying the page_views.page_views and auditors.grade_changes tables
# using a WHERE condition for the context_id column.
#
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
      account.courses.each do |course|
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
      return []
    end
    unless (course.active_course_sections.select {|s| s.student_enrollments.length > 0}.length) > 1
      Rails.logger.info "[SECTION-SPLITTER] Skipping course #{course.id}: does not contain multiple sections with enrollments"
      return []
    end

    Rails.logger.info "[SECTION-SPLITTER] Splitting course #{course.id} [#{course.name}]..."
    result = []

    start_ts = Time.now
    begin
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
    ensure
      clean_delayed_jobs(course, start_ts)
    end

    result
  end

  def self.clean_delayed_jobs(course, timestamp)
    begin
      Delayed::Job.where("created_at >= ?", timestamp).each(&:destroy)
    rescue Exception => e
      Rails.logger.error "[SECTION-SPLITTER] Unable to clean up delayed jobs for course ID=#{course.id}: #{e.inspect}"
    end
  end

  def self.perform_course_copy(user, source_course, source_section, args)
    args[:name] = source_course.name
    args[:course_code] = source_section.name
    target_course = source_course.account.courses.new
    target_course.attributes = args
    target_course.workflow_state = source_course.workflow_state
    source_course.settings.each do |setting|
      target_course.send("#{setting[0]}=".to_sym, setting[1])
    end
    target_course.dynamic_tab_configuration = source_course.dynamic_tab_configuration.clone
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
      Rails.logger.error "[SECTION-SPLITTER] Unable to perform course copy (content migration ID=#{content_migration.id}) for course ID=#{source_course.id} [#{source_course.name}]: #{e.inspect}"
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
      Rails.logger.error "[SECTION-SPLITTER] Unable to migrate source section ID=#{source_section.id} to target course ID=#{target_course.id}: #{e.inspect}"
    end
  end

  SectionMigrationWorker = Struct.new(:target_course_id, :source_section_id) do
    def perform
      @target_course = Course.find(target_course_id)
      @source_section = CourseSection.find(source_section_id)
      @source_course = @source_section.course
      @source_asset_strings = {}

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
      migrate_page_views_and_audit_logs
      migrate_asset_user_accesses
      migrate_content_participation_counts
      migrate_custom_gradebook_columns
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
        elsif model.is_a?(Assignment)
          if model.quiz.present?
            @target_course.quizzes.delete(model.quiz)
            model.quiz.assignment_overrides.each {|o| o.destroy_permanently!}
            model.quiz.destroy_permanently!
          end
          if model.discussion_topic.present?
            DiscussionTopic::MaterializedView.for(model.discussion_topic).destroy
            @target_course.discussion_topics.delete(model.discussion_topic)
            model.discussion_topic.assignment_overrides.each {|o| o.destroy_permanently!}
            model.discussion_topic.destroy_permanently!
          end
        end
        collection.delete(model)
        model.assignment_overrides.each {|o| o.destroy_permanently!}
        model.destroy_permanently!
      end
    end

    def clean_calendar_events
      @source_course.calendar_events.active.where("course_section_id IS NOT NULL AND course_section_id <> ?", @source_section.id).each do |source_event|
        target_event = source_model(@target_course, source_event)
        target_event.destroy_permanently!
      end
      @source_course.reload
      @target_course.reload
    end

    def remove_based_on_overrides?(model)
      # The model should be included in the target course if the source model has no assignment overrides, or
      # if the the overrides reference the source section or a student from the source section
      return false if model.active_assignment_overrides.empty?
      student_ids = @source_section.student_enrollments.map(&:user_id)
      model.active_assignment_overrides.select {|ao| (ao.set_type == 'CourseSection' && ao.set_id == @source_section.id) ||
        (ao.set_type == 'ADHOC' && (student_ids & ao.assignment_override_students.map(&:user_id)).any?)}.empty?
    end

    # Uses heuristics to locate the corresponding source content item in the source course for the given item in the target course.
    def source_model(source_course, model)
      source_model =
        case model
          when Announcement
            source_course.announcements.where(:workflow_state => model.workflow_state, :title => model.title).first
          when Assignment
            target_modules = model.context_module_tags.where(:context => model.context).map {|t| t.context_module.name}.sort
            models = source_course.assignments.where(:workflow_state => model.workflow_state, :title => model.title)
            models.select! {|m| m.context_module_tags.where(:context => source_course).map {|t| t.context_module.name}.sort == target_modules}
            models.first
          when DiscussionTopic
            target_modules = model.context_module_tags.where(:context => model.context).map {|t| t.context_module.name}.sort
            models = source_course.discussion_topics.where(:workflow_state => model.workflow_state, :title => model.title)
            models.select! {|m| m.context_module_tags.where(:context => source_course).map {|t| t.context_module.name}.sort == target_modules}
            models.first
          when Quizzes::Quiz
            target_modules = model.context_module_tags.where(:context => model.context).map {|t| t.context_module.name}.sort
            models = source_course.quizzes.where(:workflow_state => model.workflow_state, :title => model.title, :question_count => model.question_count)
            models.select! {|m| m.context_module_tags.where(:context => source_course).map {|t| t.context_module.name}.sort == target_modules}
            models.first
          when CalendarEvent
            source_course.calendar_events.where(:workflow_state => model.workflow_state, :title => model.title, :start_at => model.start_at, :end_at => model.end_at).first
          when GroupCategory
            source_course.group_categories.where(:name => model.name, :role => model.role, :deleted_at => model.deleted_at, :group_limit => model.group_limit).first
          else
            nil
        end
      raise "Unable to find source item for [#{model.inspect}] in course ID=#{source_course.id}" unless source_model
      @source_asset_strings[source_model.asset_string] = model.asset_string if source_course == @source_course
      source_model
    end

    def migrate_section
      @source_section.course = @target_course
      @source_section.default_section = true
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
      model.only_visible_to_overrides = source_model.only_visible_to_overrides
      model.save!
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
      group_category_map = {}
      @source_course.group_categories.each do |gc|
        new_category = gc.clone
        new_category.context = @target_course
        @target_course.group_categories << new_category
        @target_course.save
        group_category_map[gc] = new_category
      end
      groups = @source_course.groups.where(:course_section_id => @source_section.id)
      groups.each do |group|
        next unless group.group_category
        new_category = group_category_map[group.group_category]
        group.group_category = new_category
        group.save
      end
      groups.update_all(:context_id => @target_course.id)
      @source_course.reload
      @target_course.reload
    end

    def migrate_submissions
      student_ids = @target_course.student_enrollments.map(&:user_id)
      @target_course.assignments.each do |a|
        Submission.where(:assignment => a, :user_id => student_ids).delete_all
        source_assignment = source_model(@source_course, a)
        submissions = Submission.where(:assignment => source_assignment, :user_id => student_ids)
        submissions.select {|s| s.attachment_ids.present? }.each do |s|
          attachment_ids = s.attachment_ids.split(",")
          Attachment.where(:id => attachment_ids, :context_type => 'Assignment', :context_id => source_assignment.id).update_all(:context_id => a.id)
        end
        submission_comments = SubmissionComment.where(:submission_id => submissions.map(&:id), :context => @source_course)
        submission_comments.update_all(:context_id => @target_course.id)
        submissions.update_all(:assignment_id => a.id)
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
      # Update references to the new discussion topics
      section_user_ids = @target_course.enrollments.map(&:user_id).uniq
      @target_course.discussion_topics.each do |topic|
        source_topic = source_model(@source_course, topic)
        source_topic.root_discussion_entries.each do |entry|
          entry_ids = ([entry.id] + entry.flattened_discussion_subentries.pluck(:id)).uniq
          participant_ids = ([entry.user_id] + entry.flattened_discussion_subentries.pluck(:user_id)).uniq
          non_section_participant_ids = participant_ids - section_user_ids
          if non_section_participant_ids.empty?
            DiscussionEntry.where(:id => entry_ids).update_all(:discussion_topic_id => topic.id)
            DiscussionEntryParticipant.where("discussion_entry_id IN (?) AND user_id NOT IN (?)", entry_ids, section_user_ids).delete_all
          end
        end
        source_topic.discussion_topic_participants.where(:user_id => section_user_ids).update_all(:discussion_topic_id => topic.id)
        source_topic.reload
        topic.last_reply_at = topic.discussion_entries.last.try(:created_at) || topic.posted_at
        topic.save
        DiscussionTopic.where(:id => topic.id).update_all(:user_id => source_topic.user_id) # ugly hack, but user_id is a readonly attribute
      end
      @source_course.reload
      @target_course.reload

      # Update links within discussion entries
      @target_course.discussion_entries.where("discussion_entries.message ~ '/courses/#{@source_course.id}'").each do |entry|
        new_message = entry.message.gsub(/\/courses\/#{@source_course.id}/, "/courses/#{@target_course.id}")
        DiscussionEntry.where(:id => entry.id).update_all(:message => new_message)
      end

      # Regenerate materialized views
      @target_course.discussion_topics.each do |topic|
        begin
          DiscussionTopic::MaterializedView.for(topic).update_materialized_view_without_send_later
        rescue Exception => e
          Canvas::Errors.capture_exception(:section_splitter, $ERROR_INFO)
          Rails.logger.error "Unable to regenerate DiscussionTopic::MaterializedView for ID=#{topic.id}: #{e.inspect}"
        end
      end
    end

    def migrate_messages
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.messages.where(:user_id => user_ids).update_all(:context_id => @target_course.id)
      @source_course.reload
      @target_course.reload
    end

    def migrate_page_views_and_audit_logs
      user_ids = @target_course.enrollments.map(&:user_id)
      if cassandra?
        migrate_page_views_cassandra(user_ids)
        migrate_page_views_counters_by_context_and_hour(user_ids)
        migrate_page_views_counters_by_context_and_user(user_ids)
        migrate_participations_by_context(user_ids)
        migrate_grade_changes(user_ids)
      else
        @source_course.page_views.where(:user_id => user_ids).each do |p|
          p.context = @target_course
          p.save
        end
      end
    end

    def migrate_page_views_cassandra(user_ids)
      page_views = []
      PageView::EventStream.database.execute("SELECT request_id, context_type, user_id, created_at, controller, participated FROM page_views WHERE context_id = ?", @source_course.id).fetch {|row| page_views << row.to_hash}
      page_views.select! {|row| row["context_type"] == "Course" && user_ids.include?(row["user_id"].to_i)}
      infer_page_views_rollups(page_views)
      request_ids = page_views.map {|row| row["request_id"]}.uniq
      PageView::EventStream.database.update("UPDATE page_views SET context_id = ? WHERE request_id IN (?)", @target_course.id, request_ids)
    end

    def infer_page_views_rollups(page_views)
      binned_page_views(page_views).each do |data|
        PageView.transaction do
          # Augment bin for target course
          bin = PageViewsRollup.bin_for(@target_course.id, data[:date], data[:category])
          bin.augment(data[:views], data[:participations])
          bin.save!

          # Decrement bin for source course
          bin = PageViewsRollup.bin_for(@source_course.id, data[:date], data[:category])
          next unless bin
          bin.augment(-data[:views], -data[:participations])
          bin.save!
        end
      end
    end

    CONTROLLERS_TO_CATEGORIES = {
      :assignments => :assignments,
      :courses => :general,
      :quizzes => :quizzes,
      :wiki_pages => :pages,
      :gradebooks => :grades,
      :submissions => :assignments,
      :discussion_topics => :discussions,
      :files => :files,
      :context_modules => :modules,
      :announcements => :announcements,
      :collaborations => :collaborations,
      :conferences => :conferences,
      :groups => :groups,
      :question_banks => :quizzes,
      :gradebook2 => :grades,
      :wiki_page_revisions => :pages,
      :folders => :files,
      :grading_standards => :grades,
      :discussion_entries => :discussions,
      :assignment_groups => :assignments,
      :quiz_questions => :quizzes,
      :gradebook_uploads => :grades
    }

    def binned_page_views(page_views)
      bins = []
      page_views.each do |page_view|
        next unless page_view["controller"]
        date = page_view["created_at"].to_date
        category = Analytics::Extensions::PageView::CONTROLLER_TO_ACTION[page_view["controller"].to_sym] || :other
        bin = bins.find {|bin| bin[:date] == date && bin[:category] == category}
        unless bin
          bin = {
            :date => date,
            :category => category,
            :views => 0,
            :participations => 0
          }
          bins << bin
        end
        bin[:views] += 1
        bin[:participations] += 1 if page_view["participated"]
      end
      bins
    end

    def migrate_page_views_counters_by_context_and_hour(user_ids)
      source_course_global_id = @source_course.global_id
      target_course_global_id = @target_course.global_id
      user_ids.each do |user_id|
        user_global_id = User.find(user_id).global_id
        source_context_user_global_id = "course_#{source_course_global_id}/user_#{user_global_id}"
        target_context_user_global_id = "course_#{target_course_global_id}/user_#{user_global_id}"
        page_views_counters_by_context_and_hour = []
        query = "SELECT context, hour_bucket, page_view_count, participation_count FROM page_views_counters_by_context_and_hour WHERE context = ?"
        PageView::EventStream.database.execute(query, source_context_user_global_id).fetch {|row| page_views_counters_by_context_and_hour << row.to_hash}
        page_views_counters_by_context_and_hour.each do |row|
          primary_key = {
            "context" => target_context_user_global_id,
            "hour_bucket" => row["hour_bucket"]
          }
          PageView::EventStream.database.insert_record("page_views_counters_by_context_and_hour", primary_key, {})
          if row["page_view_count"]
            PageView::EventStream.database.update("UPDATE page_views_counters_by_context_and_hour SET page_view_count = page_view_count + ? WHERE context = ? AND hour_bucket = ?", row["page_view_count"], primary_key["context"], primary_key["hour_bucket"])
          end
          if row["participation_count"]
            PageView::EventStream.database.update("UPDATE page_views_counters_by_context_and_hour SET participation_count = participation_count + ? WHERE context = ? AND hour_bucket = ?", row["participation_count"], primary_key["context"], primary_key["hour_bucket"])
          end
          PageView::EventStream.database.update("DELETE FROM page_views_counters_by_context_and_hour WHERE context = ? AND hour_bucket = ?", source_context_user_global_id, row["hour_bucket"])
        end
      end
    end

    def migrate_page_views_counters_by_context_and_user(user_ids)
      source_course_global_id = @source_course.global_id
      target_course_global_id = @target_course.global_id
      user_ids.each do |user_id|
        user_global_id = User.find(user_id).global_id.to_s
        source_context_global_id = "course_#{source_course_global_id}"
        target_context_global_id = "course_#{target_course_global_id}"
        page_views_counters_by_context_and_user = []
        query = "SELECT context, user_id, page_view_count, participation_count FROM page_views_counters_by_context_and_user WHERE context = ? AND user_id = ?"
        PageView::EventStream.database.execute(query, source_context_global_id, user_global_id).fetch {|row| page_views_counters_by_context_and_user << row.to_hash}
        page_views_counters_by_context_and_user.each do |row|
          primary_key = {
            "context" => target_context_global_id,
            "user_id" => user_global_id
          }
          PageView::EventStream.database.insert_record("page_views_counters_by_context_and_user", primary_key, {})
          if row["page_view_count"]
            PageView::EventStream.database.update("UPDATE page_views_counters_by_context_and_user SET page_view_count = page_view_count + ? WHERE context = ? AND user_id = ?", row["page_view_count"], primary_key["context"], primary_key["user_id"])
          end
          if row["participation_count"]
            PageView::EventStream.database.update("UPDATE page_views_counters_by_context_and_user SET participation_count = participation_count + ? WHERE context = ? AND user_id = ?", row["participation_count"], primary_key["context"], primary_key["user_id"])
          end
          PageView::EventStream.database.update("DELETE FROM page_views_counters_by_context_and_user WHERE context = ? AND user_id = ?", source_context_global_id, user_global_id)
        end
      end
    end

    def migrate_participations_by_context(user_ids)
      source_course_global_id = @source_course.global_id
      target_course_global_id = @target_course.global_id
      user_ids.each do |user_id|
        user_global_id = User.find(user_id).global_id
        source_context_user_global_id = "course_#{source_course_global_id}/user_#{user_global_id}"
        target_context_user_global_id = "course_#{target_course_global_id}/user_#{user_global_id}"
        participations_by_context = []
        query = "SELECT context, created_at, request_id, asset_category, asset_code, asset_user_access_id, url FROM participations_by_context WHERE context = ?"
        PageView::EventStream.database.execute(query, source_context_user_global_id).fetch {|row| participations_by_context << row.to_hash}
        participations_by_context.each do |row|
          values = {
            "asset_category" => row["asset_category"],
            "asset_code" => @source_asset_strings[row["asset_code"]],
            "asset_user_access_id" => row["asset_user_access_id"],
            "url" => row["url"]
          }
          primary_key = {
            "context" => target_context_user_global_id,
            "created_at" => row["created_at"],
            "request_id" => row["request_id"]
          }
          if values["asset_code"].present?
            PageView::EventStream.database.insert_record("participations_by_context", primary_key, values)
            PageView::EventStream.database.update("DELETE FROM participations_by_context WHERE context = ? AND created_at = ? AND request_id = ?", source_context_user_global_id, row["created_at"], row["request_id"])
          end
        end
      end
    end

    def migrate_grade_changes(user_ids)
      source_course_global_id = @source_course.global_id
      target_course_global_id = @target_course.global_id
      user_global_ids = user_ids.map {|user_id| User.find(user_id).global_id}
      grade_changes = []
      query = "SELECT id, assignment_id, context_id, context_type, student_id FROM grade_changes WHERE context_id = ?"
      Auditors::GradeChange::Stream.database.execute(query, source_course_global_id).fetch {|row| grade_changes << row.to_hash}
      grade_changes.select! {|row| row["context_type"] == "Course" && user_global_ids.include?(row["student_id"])}
      grade_changes.each do |row|
        assignment_id = Shard::local_id_for(row["assignment_id"])[0]
        assignment = Assignment.find(assignment_id)
        next unless assignment
        new_assignment = source_model(@target_course, assignment)
        values = {
          "assignment_id" => new_assignment.id,
          "context_id" => target_course_global_id
        }
        primary_key = {
          "id" => row["id"]
        }
        Auditors::GradeChange::Stream.database.update_record("grade_changes", primary_key, values)
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

    def migrate_custom_gradebook_columns
      user_ids = @target_course.enrollments.map(&:user_id)
      @source_course.custom_gradebook_columns.each do |column|
        new_column = column.clone
        column.custom_gradebook_column_data.where(:user_id => user_ids).each do |datum|
          new_column.custom_gradebook_column_data << datum
        end
        new_column.course = @target_course
        @target_course.custom_gradebook_columns << new_column
        new_column.save!
      end
      @target_course.save!
    end

    def cassandra?
      Setting.get('enable_page_views', 'db') == 'cassandra'
    end
  end
end
