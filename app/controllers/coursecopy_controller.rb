require 'csv'

class CoursecopyController < ApplicationController
  include Api::V1::Account
  before_filter :require_context, :require_account_management

  def index
    # @course_copy = {:course_copy => []}
    @csvfile = Hash.new
    @csvfile[:file] = []
    if @context && @context.is_a?(Account)
      # @course_copy[:help_setup_links] = @context.settings[:help_setup_links] || []
      js_env(:current_account => @context, :url => context_url(@context, :context_coursecopy_index_url))
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

  def load_file
    uploaded_io = params[:csvfile][:file]
    CSV.foreach("/Users/jsoto/B/RUBY/course_copy.csv", :headers => true, :header_converters => :symbol, :converters => :all) do |row|  
      if row.count == 2
        puts "Row info: #{row}"   
      end   
    end  
  end

end
