
#Hotchalk Course Library functionality
class HotchalkCourseLibraryController < ApplicationController

	def search
		#TODO validate user permissions to use CL. 
		client = init_client
		if client
			query_text = params[:query] ? params[:query] : ''
			subtype = params[:subtype] ? params[:subtype] : ''
			course_id = params[:usedIn] ? params[:usedIn] : ''
			searchParams = { :_type => "learningObject", 
							 :query => query_text,
							 :subtype => subtype,
							 :usedIn => course_id,
							 :sortBy => "MODIFIED", 
							 :sortOrder => "DESC"}
			response = client.json_request(:get,"/search", searchParams)
			render(:json => response.body, :status => response.code)
		end
	end

	def curricula
		client = init_client
		if client
			response =  client.json_request(:get,"/curricula")
			render(:json => response.body, :status => response.code)
		end
	end

	def init_client
		begin
			client = CourseLibrary::Client.new(params[:root_account_id],@current_user.id)
			return client
		rescue => e
			render(:json => { :message => t('invalid_account_external_urls', "Invalid Hotchalk plugin settings for this account") }, :status => :bad_request)
			return nil
		end
	end

end