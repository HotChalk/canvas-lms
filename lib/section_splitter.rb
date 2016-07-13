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
      Rails.logger.info "In SectionMigrationWorker::perform[#{target_course_id},#{source_section_id}]"
    end
  end
end
