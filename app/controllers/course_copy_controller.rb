require 'csv'
require 'date'

class CourseCopyController < ApplicationController
  include Api::V1::Account
  include Api::V1::ContentMigration

  before_filter :require_account_context

  def index
    return unless authorized_action(@context, @current_user, :manage_content)
    migrations = ContentMigration.where(context_type: 'Account', context_id: @context.id, workflow_state: ['created', 'exporting','queued']).order('id desc')    
    js_env({
               :current_account => @context,
               :url => context_url(@context, :context_course_copy_index_url),
               :content_migrations => migrations,
               :progress_url => context_url(@context, :context_course_copy_progress_url)
           })
  end

  def history
    return unless authorized_action(@context, @current_user, :manage_content)
    cm = ContentMigration.where("context_type = :context AND context_id = :context_id AND workflow_state in (:state) AND created_at >= :created ",
                          :context => 'Account',
                          :context_id => @context.id,
                          :state => ['imported','failed'],
                          :created => 1.month.ago.to_date).order('id desc')

    sync_migration_progresses(cm)
    js_env(:current_account => @context, :url => context_url(@context, :context_course_copy_history_url), :content_migrations => cm)
  end

  def progress
    cm = ContentMigration.where(context_type: 'Account', context_id: @context.id, workflow_state: ['created','exporting','queued'], migration_type: 'course_copy_tool_csv_importer').order('id desc')
    sync_migration_progresses(cm)
    render :json => cm
  end

  def sync_migration_progresses(migrations)
    migrations.each do |migration|
      results = migration.migration_settings[:results]      
      failed = false
      running = false
      if results.length > 0
        results.each do |result|
          next unless result[:content_migration_id] && (cm = ContentMigration.find(result[:content_migration_id]))
          result[:workflow_state] = cm.workflow_state
          result[:completion] = cm.progress
          result[:finished_at] = cm.finished_at
          migration.migration_settings[:results] = results
          migration.save!
        end
        # if all the migrations are completed, the course copy migration have to be updated marked like completed
        pending_migrations = results.count {|migration| ['created', 'queued', 'exporting'].include?(migration[:workflow_state]) }
        if pending_migrations == 0
          migration.workflow_state = :imported
          migration.finished_at = results.map {|m| m[:finished_at]}.compact.max
          migration.updated_at = migration[:finished_at]
          migration.save!
          migration.update_import_progress(100)
        end     
      end      
    end
  end

  def get_plugin
    @plugin = Canvas::Plugin.find('course_copy_tool_csv_importer')
    raise t('plugin_disabled', "Plugin is disabled") unless @plugin.present? && @plugin.enabled?
  end

  def create
    begin
      # Validate plugin and params
      get_plugin
      raise t('must_upload_file', "File upload is required") unless params[:file].present?

      # Parse uploaded CSV and create content migration
      @csv_data = read_csv_file
      @content_migration = @context.content_migrations.build(
        user: @current_user,
        context: @context,
        migration_type: 'course_copy_tool_csv_importer',
        initiated_source: :api
      )
      @content_migration.workflow_state = 'created'
      @content_migration.migration_settings[:import_immediately] = true
      @content_migration.migration_settings[:csv_data] = @csv_data
      @content_migration.migration_settings[:due_dates] = params[:due_dates] || 0
      @content_migration.migration_settings[:results] = []
      
      if @content_migration.save
        @content_migration.queue_migration(@plugin)
      end
    rescue Exception => e
      flash[:error] = "Course copy tool failed. Please contact your system administrator. #{e.message}"
      logger.error "ERROR: Unable to launch course copy: #{e.message}"
    end
    return redirect_to context_url(@context, :context_course_copy_index_url)
  end

  def read_csv_file
    csv_table = CSV.table(params[:file].path, {:headers => true, :header_converters => :symbol, :converters => :all})
    raise t('incorrect_csv_headers', "Incorrect CSV headers") unless csv_table.headers == [:master, :target]
    data_arr = csv_table.to_a.drop(1)
    raise t('csv_empty', "CSV does not have any data to process") unless data_arr.length > 0
    data_arr
  end

end
