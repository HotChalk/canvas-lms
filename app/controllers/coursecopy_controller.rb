require 'csv'
require 'date'

class CoursecopyController < ApplicationController
  include Api::V1::Account
  include Api::V1::ContentMigration

  before_filter :require_context, :require_account_management

  def index
    @csvfile = Hash.new
    @csvfile[:file] = []

    @csvfile

    # se ejecuta el script de python ... para ver si funca... solo para testing
    # execPythonFile()

    if @context && @context.is_a?(Account)      
      cm = ContentMigration.where context_type: 'Account', context_id: @context.id, workflow_state: ['exporting','queued']
      puts "JUAN... estoy consultadon las content_migrations... "
      puts "cm #{cm.inspect}"
      js_env(:current_account => @context, :url => context_url(@context, :context_coursecopy_index_url), :content_migrations => cm, :progress_url => account_coursecopy_progress_path )
    end
  end  

  def history
    if @context && @context.is_a?(Account)      
      # cm = ContentMigration.where context_type: 'Account', context_id: @context.id, workflow_state: 'imported'
      cm = ContentMigration.where context_type: 'Account', context_id: @context.id, workflow_state: ['imported','failed']      
      js_env(:current_account => @context, :url => context_url(@context, :context_coursecopy_history_url), :content_migrations => cm)
    end
  end  
  
  def progress
    if @context && @context.is_a?(Account)      
      cm = ContentMigration.where context_type: 'Account', context_id: @context.id, workflow_state: ['exporting','queued']
      puts "JUAN... estoy consultadon las content_migrations... "
      puts "cm #{cm.inspect}"
      render :json => cm
    end
  end  

  def uri?(string)
    uri = URI.parse(string)
    %w( http https ).include?(uri.scheme)
  rescue URI::BadURIError
    false
  rescue URI::InvalidURIError
    false
  end

  def get_plugin
    result = { :plugin => nil, :status => nil, :message => "", :state => true  }
    @plugin = find_migration_plugin 'course_copy_tool_csv_importer'

    if !@plugin
      result = { :status => :bad_request, :message => t('bad_migration_type', "Invalid migration_type"), :state => false }
      return result
    end
    result[:plugin] = @plugin
    unless @plugin.enabled?
      result = { :status => :bad_request, :message => t('plugin_disabled', "Plugin is disabled."), :state => false }
      return result
    end
    unless migration_plugin_supported?(@plugin)
      result = { :status => :bad_request, :message => t('unsupported_migration_type', "Unsupported migration_type for context"), :state => false }
      return result
    end
    return result
  end

  def start_copy
    begin
      result = { :status => nil, :message => "", :state => true  }
      valid_plugin = get_plugin      
      unless valid_plugin[:state]
        return render(:json => valid_plugin)        
      end
      @plugin = valid_plugin[:plugin]
      
      settings = @plugin.settings || {}   

      if settings[:requires_file_upload]
        puts "params #{params.inspect}"
        if !(params[:file].present?)
          # result = { :status => :bad_request, :message => t('must_upload_file', "File upload or url is required"), :state => false }
          flash[:error] = t :must_upload_file, "File upload or url is required"
          redirect_to :back
        end
      end
    
      @status = true
      uploaded_io = params[:file]
      File.open(Rails.root.join('public', 'uploads', uploaded_io.original_filename), 'wb') do |file|
        file.write(uploaded_io.read)
      end

      # read file
      result = read_csv_file uploaded_io.original_filename
      unless result[:status] 
        @status = false
      end

      # set up the plugin for delayed jobs
      @content_migration = @context.content_migrations.build(
          user: @current_user,
          context: @context,
          migration_type: 'course_copy_tool_csv_importer',          
          initiated_source: :api          
      )
      @content_migration.workflow_state = 'created'
      # @content_migration.source_course = source_course if source_course

      # # Special case: check for Hotchalk package imports and add URL
      # if params[:migration_type] == 'hotchalk' && @plugin.enabled? && @context.respond_to?(:root_account)
      #   begin
      #     source_package_id = params[:settings][:source_course_id]
      #     base_url = settings[:account_external_urls][@context.root_account_id.to_s]['cl_base_url']
      #     integration_key = settings[:account_external_urls][@context.root_account_id.to_s]['cl_integration_key']
      #     raise "Invalid Hotchalk plugin settings for account ID #{@context.root_account_id}" if base_url.blank? || integration_key.blank?
      #     package_url = "https://#{base_url}/clws/integration/packages/#{source_package_id}/download?key=#{integration_key}"
      #     params[:pre_attachment] = { :url => package_url, :name => "#{source_package_id}.imscc" }
      #   rescue => e
      #     @content_migration.fail_with_error!(e)
      #     render :json => @content_migration.errors, :status => :bad_request
      #     return
      #   end
      # end

      update_migration

    rescue => ex
      puts "ex #{ex}"
      result[:state] = false
    end
    
    # respond_to do |format|
    #   flash[:error] = t(result[:message])
    #   format.html { redirect_to context_url(@context, :context_coursecopy_index_url) }
    #   format.json { render :json => result }
    # end
  end

  def update_migration
    # result = { :status => nil, :message => "", :state => true  }
    # @content_migration.update_migration_settings(params[:settings]) if params[:settings]
    # @content_migration.set_date_shift_options(params[:date_shift_options])

    params[:selective_import] = false if @plugin.settings && @plugin.settings[:no_selective_import]
    if Canvas::Plugin.value_to_boolean(params[:selective_import])
      @content_migration.migration_settings[:import_immediately] = false
      if @plugin.settings[:skip_conversion_step]
        # Mark the migration as 'waiting_for_select' since it doesn't need a conversion
        # and is selective import
        @content_migration.workflow_state = 'exported'
        params[:do_not_run] = true
      end
    elsif params[:copy]
      copy_options = ContentMigration.process_copy_params(params[:copy])
      copy_options.merge!({ 'all_learning_outcome_groups' => '1' }) if copy_options['all_learning_outcomes'] == '1'
      @content_migration.migration_settings[:migration_ids_to_import] ||= {}
      @content_migration.migration_settings[:migration_ids_to_import][:copy] = copy_options
      @content_migration.copy_options = copy_options
    else
      @content_migration.migration_settings[:import_immediately] = true
      @content_migration.copy_options = {:everything => true}
      @content_migration.migration_settings[:migration_ids_to_import] = {:copy => {:everything => true}}
    end

    uploaded_io = params[:file]
    @content_migration.migration_settings[:filename] = uploaded_io.original_filename        
    @content_migration.migration_settings[:due_dates] = params[:due_dates] || 0
    if @content_migration.migration_settings[:due_dates] == '1'
      @content_migration.migration_settings[:new_start_date] = Date.today
    end
    
    if @content_migration.save
      preflight_json = nil
      if params[:pre_attachment]        
        @content_migration.workflow_state = 'pre_processing'
        preflight_json = api_attachment_preflight(@content_migration, request, :params => params[:pre_attachment], :check_quota => true, :return_json => true)
        if preflight_json[:error]
          @content_migration.workflow_state = 'pre_process_error'
        end
        @content_migration.save!
      elsif !params.has_key?(:do_not_run) || !Canvas::Plugin.value_to_boolean(params[:do_not_run])
        @content_migration.queue_migration(@plugin)
      end

      # render :json => content_migration_json(@content_migration, @current_user, session, preflight_json)
      content_migration_json(@content_migration, @current_user, session, preflight_json)
      # render "index"
      redirect_to :back
    else
      render :json => @content_migration.errors, :status => :bad_request
    end
  end


  def read_csv_file filename
    result = { :status => true, :message => "" }

    CSV.foreach(Rails.root.join('public', 'uploads', filename), :headers => true, :header_converters => :symbol, :converters => :all) do |row|
      if row.count == 2
        # find master
        unless Course.exists?(row[0])
          result = { :status => false, :error => 404, :message => "Master Course Id: #{row[0]} Not Found" }
          break
        end
        # find target
        unless Course.exists?(row[1])
          puts "Not Found"
          result = { :status => false, :error => 404, :message => "Target Course Id: #{row[1]} Not Found" }
          break
        end
      end
    end
    result
  end

  def find_migration_plugin(name)
    if name =~ /context_external_tool/
      plugin = Canvas::Plugin.new(name)
      plugin.meta[:settings] = {requires_file_upload: true, worker: 'CCWorker', valid_contexts: %w{Account}}.with_indifferent_access
      plugin
    else
      Canvas::Plugin.find(name)
    end
  end

  def migration_plugin_supported?(plugin)    
    Array(plugin.default_settings && plugin.default_settings[:valid_contexts]).include?(@context.class.to_s)
  end

  def execPythonFile()
    filename = 'CourseCopy.py'    
    file_path = Rails.root.join('vendor', 'CourseCopyTool', filename).to_s rescue nil
    unless File.exist?(file_path)
      result = { :status => :bad_request, :message => t('must_script_file', "Python script file is required"), :state => false }
      return result
    end

    # exec the python file
    # prepend = ""
    # script_txt = "\"#{file_path}\" #{prepend}--ucvars --nogui --overwrite"
    obj = {
      master_id: 1,
      target_id: 3,
      modify_dates: 'Y',
      master_start_at: DateTime.now,
      master_conclude_at: DateTime.now, 
      start_date: DateTime.now
    }

    # python_std_out = `python #{file_path} #{obj.to_json}`
    # puts "JUAN SE EJECUTA EL PYTHON SCRIPT... #{python_std_out.inspect}"

  end

end
