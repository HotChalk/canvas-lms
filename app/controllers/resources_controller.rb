class ResourcesController < ApplicationController
  include Api::V1::Account
  before_filter :require_context, :require_account_management

  def index
    @resources = {:enable_resources_link => false, :resources_links => []}
    if @context && @context.is_a?(Account)
      @resources[:enable_resources_link] = @context.settings[:enable_resources_link]
      @resources[:resources_links] = @context.settings[:resources_links] || []
    end
  end

  def update
    if @context.is_a?(Account) && authorized_action(@context, @current_user, :manage_account_settings)
      respond_to do |format|
        @context.settings[:resources_links] = params[:resources_links]
        if params[:enable_resources_link]
          @context.settings[:enable_resources_link] = true
        else
          @context.settings[:enable_resources_link] = false
        end
        if params[:resources_links]
          params[:resources_links].each do |title, url|
            @context.errors.add(:title) unless title.present?
            @context.errors.add(:url) unless url.present? && uri?(url)
          end
        end
        if @context.errors.empty? && @context.update_attributes(@context.settings)
          format.html { redirect_to account_resources_links_index_url(@context) }
          format.json { render :json => @context }
        else
          flash[:error] = (@context.errors.full_messages.uniq.join('. '))
          format.html { redirect_to account_resources_links_index_url(@context) }
          format.json { render :json => @context.errors, :status => :bad_request }
        end
      end
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

end
