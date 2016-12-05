require 'csv'

class Course_copy_tool_exception < StandardError
  attr_reader :data
  def initialize(msg="Course Copy Tool Exception", data_error={})
    @data = data_error
    super(msg)
  end
end

class Canvas::Migration::Worker::CourseCopyToolCsvFileWorker < Canvas::Migration::Worker::Base
  def perform(cm=nil)
    cm ||= ContentMigration.find migration_id

    cm.workflow_state = :pre_processing
    cm.reset_job_progress
    cm.migration_settings[:skip_import_notification] = true
    cm.migration_settings[:import_immediately] = true
    cm.migration_settings[:results] = []
    cm.save
    cm.job_progress.start    

    cm.shard.activate do
      begin
        cm.workflow_state = :exporting
        cm.save
        csv_data = cm.migration_settings[:csv_data]
        cm.migration_settings[:total_copy] = csv_data.length
        cm.migration_settings[:number_processed] = 0
        cm.save
        csv_data.each do |row|
          result = process_csv_row(row, cm)
          cm.migration_settings[:results] << result
          if result[:workflow_state] == :failed
            cm.migration_settings[:number_processed] += 1
          end
          cm.save
        end                
      rescue => e
        cm.fail_with_error!(e)
        raise e
      end
    end
  end

  def getCourseUrl(id)    
    "/courses/#{id}"
  end

  def process_csv_row(row, cm)
    result = {}
    begin
      result.merge!({:master_id => row[0], :target_id => row[1]})
      validate_csv_row(row)      
      master = Course.find(row[0])      
      result.merge!({:master_name => master.name, :master_code_id => master.course_code, :master_section_name => master.default_section.section_code, :master_url => getCourseUrl(row[0])})
      
      target = Course.find(row[1])
      result.merge!({:target_name => target.name, :target_code_id => target.course_code, :target_section_name => target.default_section.section_code, :target_url => getCourseUrl(row[1])})

      date_shift_options = {:shift_dates => (cm.migration_settings[:due_dates] == '1')}
      
      if date_shift_options[:shift_dates]
        date_shift_options[:old_start_date] = master.start_at.to_s
        date_shift_options[:old_end_date] = master.conclude_at.to_s
        date_shift_options[:new_start_date] = target.start_at.to_s
      end

      settings = {:source_course_id => master.id, :migration_source_id => cm.id}
      params = {:migration_type => 'course_copy_importer', :date_shift_options => date_shift_options, :settings => settings}      
      migration = create_migration(master, target, params, cm.user)
      result.merge!({:workflow_state => :queued, :content_migration_id => migration.id, :completion => 0, :created_at => migration.created_at, :updated_at => migration.updated_at})
    rescue Exception => e
      result.merge!({:workflow_state => :failed, :error_msg => e.message, :data => e.data})
    end
    result
  end

  def validate_csv_row(row)
    raise Course_copy_tool_exception.new("Wrong row configuration - Number of columns on row is different than two" , { :state => "Error",  :error => 405 } ) unless row.length == 2
    raise Course_copy_tool_exception.new( "Master Course Id and Target Course Id are equal; Id: #{row[0]}" , { :state => "Error",  :error => 404 } ) unless row[0] != row[1]
    raise Course_copy_tool_exception.new( "Master Course Id: #{row[0]} Not Found", { :state => "Error",  :error => 404 } ) unless Course.exists?(row[0])
    raise Course_copy_tool_exception.new( "Target Course Id: #{row[1]} Not Found", { :state => "Error",  :error => 404 } ) unless Course.exists?(row[1])
  end

  def create_migration(master, target, params, user)
    plugin = Canvas::Plugin.find('course_copy_importer')
    settings = plugin.settings || {}
    if validator = settings[:required_options_validator]
      if res = validator.has_error(params[:settings], user, master)
        raise res
      end
    end

    content_migration = target.content_migrations.build(
      user: user,
      context: target,
      migration_type: 'course_copy_importer',
      initiated_source: :api
    )
    content_migration.workflow_state = 'created'
    content_migration.source_course = master
    content_migration.update_migration_settings(params[:settings]) if params[:settings]
    content_migration.set_date_shift_options(params[:date_shift_options])
    content_migration.migration_settings[:import_immediately] = true
    content_migration.copy_options = {:everything => true}
    content_migration.migration_settings[:migration_ids_to_import] = {:copy => {:everything => true}}

    if content_migration.save
      content_migration.queue_migration(plugin)
    else
      raise content_migration.errors.join('\n')
    end
    content_migration
  end

end
