class HelpsetupController < ApplicationController
  include Api::V1::Account
  before_filter :require_context, :require_account_management

  def index
    @help_setup = {:help_setup => []}
    if @context && @context.is_a?(Account)
      @help_setup[:help_setup_links] = @context.settings[:help_setup_links] || []
      js_env(:current_account => @context, :url => context_url(@context, :context_helpsetup_url))
    end
  end

  def update
    if @context.is_a?(Account) && authorized_action(@context, @current_user, :manage_account_settings)
      respond_to do |format|
        @context.settings[:help_setup_links] = @context.settings[:help_setup_links] || []
        @context.errors.add(:title) unless params[:title]
        @context.errors.add(:url) unless params[:url]
        @context.errors.add(:description) unless params[:description]
        # @context.errors.add(:x_id) unless params[:x_id]
        # @context.errors.add(:x_classes) unless params[:x_classes]
        # @context.errors.add(:javascript_txt) unless params[:javascript_txt]

        help_option = {
            :title => params[:title],
            :url => params[:url],
            :description => params[:description],
            :x_id => params[:x_id],
            :x_classes => params[:x_classes],
            :javascript_txt => params[:javascript_txt]
        }

        # update of some option already inserted
        if !params[:url_old].nil?
          option_index = @context.settings[:help_setup_links].find_index{|item| item[:url] == params[:url_old]}
          @context.settings[:help_setup_links].delete_at(option_index)
          @context.settings[:help_setup_links].insert(option_index, help_option)
        else
          @context.settings[:help_setup_links].push(help_option)
        end

        if @context.errors.empty? && @context.update_attributes(@context.settings)
          format.html { redirect_to account_helpsetup_index_url(@context) }
          format.json { render :json => @context }
        else
          flash[:error] = (@context.errors.full_messages.uniq.join('. '))
          format.html { redirect_to account_helpsetup_index_url(@context) }
          format.json { render :json => @context.errors, :status => :bad_request }
        end
      end
    end
  end

  def delete
    if @context.is_a?(Account) && authorized_action(@context, @current_user, :manage_account_settings)
      respond_to do |format|
        @context.settings[:help_setup_links] = @context.settings[:help_setup_links] || []
        @context.errors.add(:url) unless params[:url]
        
        if !params[:url].nil?
          option_index = @context.settings[:help_setup_links].find_index{|item| item[:url] == params[:url]}
          @context.settings[:help_setup_links].delete_at(option_index)
        end

        if @context.errors.empty? && @context.update_attributes(@context.settings)
          format.html { redirect_to account_helpsetup_index_url(@context) }
          format.json { render :json => @context }
        else
          flash[:error] = (@context.errors.full_messages.uniq.join('. '))
          format.html { redirect_to account_helpsetup_index_url(@context) }
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
