class SectionSplitter
  def self.run(opts)
    if opts[:course_id]
      course = Course.find(opts[:course_id])
      raise "Course not found: #{opts[:course_id]}" unless course.present?
      self.process_course(course, opts)
    end
    if opts[:account_id]
      account = Account.find(opts[:account_id])
      raise "Account not found: #{opts[:account_id]}" unless account.present?
      account.all_courses.each do |course|
        self.process_course(course, otps)
      end
    end
  end

  def self.process_course(course, opts)
    # Sanity check
    return unless course
    unless course.active_course_sections.length > 1
      self.say("Skipping course #{course.id}: not a multi-section course")
      return
    end

    self.say("Splitting course #{course.id} [#{course.title}]...")
    self.create_shells(course)
  end

  def self.create_shells(source_course)
    args = {
      :name => source_course.name,
      :enrollment_term => source_course.enrollment_term,
      :abstract_course => source_course.abstract_course,
      :account => source_course.account
    }

    source_course.active_course_sections.each do |source_section|
      self.queue_course_copy(source_course, source_section, args)
      self.queue_section_migration(source_section)
    end
  end

  def queue_course_copy(source_course, source_section, args)
    args[:course_code] = source_section.name
    target_course = source_course.account.courses.new
    target_course.attributes = args
    target_course.workflow_state = 'claimed'
    target_course.save!

    content_migration = target_course.content_migrations.build(:user => nil, :source_course => source_course, :context => target_course, :migration_type => 'course_copy_importer', :initiated_source => :manual)
    content_migration.migration_settings[:source_course_id] = source_course.id
    content_migration.workflow_state = 'created'

    content_migration.migration_settings[:import_immediately] = true
    content_migration.copy_options = {:everything => true}
    content_migration.migration_settings[:migration_ids_to_import] = {:copy => {:everything => true}}
    content_migration.workflow_state = 'importing'
    content_migration.strand = "section_splitter:#{target_course.uuid}"
    content_migration.save
    content_migration.queue_migration
  end

  def queue_section_migration(target_course, source_section)
    queue_opts = {:priority => Delayed::LOW_PRIORITY, :max_attempts => 1,
                  :expires_at => expires_at, strand: "section_splitter:#{target_course.uuid}"}
    begin
      job = Delayed::Job.enqueue(SectionMigrationWorker.new(self.id), queue_opts)
    rescue NameError
      Canvas::Errors.capture_exception(:section_splitter, $ERROR_INFO)
      Rails.logger.error message
    end
  end

  def self.say(msg)
    @logger = Rails.logger if defined?(Rails)
    if @logger
      @logger.info msg
    else
      puts msg
    end
  end

  class SectionMigrationWorker < Canvas::Migration::Worker::Base
    def perform

    end
  end
end
