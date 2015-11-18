
#Hotchalk Course Library functionality
class HotchalkCourseLibraryController < ApplicationController

	def search
		#TODO validate user permissions to use CL. 
		begin
			client = CourseLibrary::Client.new(params[:root_account_id],@current_user.id)
			query_text = params[:query] ? params[:query] : ''
			subtype = params[:subtype] ? params[:subtype] : ''
			searchParams = { :_type => "learningObject", 
							 :query => query_text,
							 :subtype => subtype, 
							 :sortBy => "MODIFIED", 
							 :sortOrder => "DESC"}
			response = client.json_request(:get,"/search", searchParams)
			render(:json => response[:json])
		rescue => e
			render(:json => { :message => t('invalid_account_external_urls', "Invalid Hotchalk plugin settings for this account") }, :status => :bad_request)
		end
	end

end