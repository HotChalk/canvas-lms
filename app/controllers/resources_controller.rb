class ResourcesController < ApplicationController
  include Api::V1::Account
  before_filter :require_context, :require_account_management

  def index
    @resources = {:enable_resources_link => false}
    @resources[:resources_links] = []
    if @context && @context.is_a?(Account) && @context.settings[:enable_resources_link]
      @resources[:enable_resources_link] = true
      @resources[:resources_links] = @context.settings[:resources_links] || []
    end
  end

  def update
    if @context.is_a?(Account) && authorized_action(@context, @current_user, :manage_account_settings)
      @context.settings[:resources_links] = params[:resources_links]
      if params[:enable_resources_link]
        @context.settings[:enable_resources_link] = true
      else
        @context.settings[:enable_resources_link] = false
      end
      
      if @context.update_attributes(@context.settings)
        format.html { redirect_to resources_links_index(@context) }
        format.json { render :json => @context }
      else
        flash[:error] = t(:update_failed_notice, "Resource links update failed")
        format.html { redirect_to resources_links_index(@context) }
        format.json { render :json => @context.errors, :status => :bad_request }
      end
    end
  end

end
