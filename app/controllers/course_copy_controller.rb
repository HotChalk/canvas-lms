require 'csv'
require 'date'

class CourseCopyController < ApplicationController
  include Api::V1::Account
  include Api::V1::ContentMigration

  before_filter :require_account_context

  def index
    return unless authorized_action(@context, @current_user, :manage_content)
    migrations = ContentMigration.where(context_type: 'Account', context_id: @context.id, workflow_state: 'exporting')
    js_env(
      :current_account => @context,
      :url => context_url(@context, :context_course_copy_index_url),
      :content_migrations => migrations,
      :progress_url => context_url(@context, :context_course_copy_progress_url)
    )
  end

  def history
    cm = ContentMigration.where(context_type: 'Account', context_id: @context.id, migration_type: 'course_copy_tool_csv_importer').where.not(workflow_state: 'exporting')
    sync_migration_progresses(cm)
    js_env(:current_account => @context, :url => context_url(@context, :context_course_copy_history_url), :content_migrations => cm)
  end

  def progress
    cm = ContentMigration.where(context_type: 'Account', context_id: @context.id, workflow_state: 'exporting', migration_type: 'course_copy_tool_csv_importer')
    sync_migration_progresses(cm)
    render :json => cm
  end

  def sync_migration_progresses(migrations)
    migrations.each do |migration|
      results = migration.migration_settings[:results]
      progress = 0
      failed = false
      running = false
      results.each do |result|
        next unless result[:content_migration_id] && (cm = ContentMigration.find(result[:content_migration_id]))
        result[:workflow_state] = cm.workflow_state
        progress += cm.progress
        failed ||= (cm.workflow_state == :failed)
        running ||= (!['failed', 'imported'].include?(cm.workflow_state))
      end
      if !running || (results.length == 0)
        migration.update_import_progress(100)
        migration.workflow_state = (failed ? :failed : :imported)
      else
        migration.update_import_progress(progress / results.length)
      end
      migration.save!
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
      # if @content_migration.migration_settings[:due_dates] == '1'
      #   @content_migration.migration_settings[:new_start_date] = Date.today
      # end
      if @content_migration.save
        @content_migration.queue_migration(@plugin)
      end
    rescue Exception => e
      flash[:error] = "Course copy tool failed. Please contact your system administrator."
      logger.error "Unable to launch course copy: #{e.message}"
    end
    render :index
  end

  def read_csv_file
    csv_table = CSV.table(params[:file].path, {:headers => true, :header_converters => :symbol, :converters => :all})
    raise t('incorrect_csv_headers', "Incorrect CSV headers") unless csv_table.headers == [:master, :target]
    csv_table.to_a.drop(1)
  end

end
