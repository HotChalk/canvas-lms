#HTTP client for Course Library services
module CourseLibrary
	class Client

		VERB_MAP = {
			:get    => Net::HTTP::Get,
			:post   => Net::HTTP::Post,
			:put    => Net::HTTP::Put,
			:delete => Net::HTTP::Delete
		}

		def initialize(account_id, user_id)
			@user_id = user_id
			@account_id = account_id.to_s
			set_account_settings
			uri = URI.parse(@cl_base)
			@http = Net::HTTP.new(uri.host, uri.port)
			#TODO check rails debug level to set debug output
			@http.set_debug_output($stdout)
		end

		def json_request(method, resource, params = {}, payload = nil)
			resource = "/clws#{resource}"
			case method
			when :get
				full_path = path_with_params(resource, params)
				request = VERB_MAP[method].new(full_path)
			else
				request = VERB_MAP[method].new(resource)
				if payload
					request.body = payload
				else
					request.set_form_data(params)
				end
			end
			add_headers(request)
			response = @http.request(request)
			return { :json => response.body, :status => response.code}
		end

		private

		def add_headers(request)
			request.add_field("Shared-Key", @key)
			request.add_field("LMS-User-Id", @user_id)
			request.add_field("Content-Type", "application/json")
		end

		def set_account_settings
			plugin = Canvas::Plugin.find(:hotchalk)
			if plugin.enabled?
				account_settings = plugin.settings[:account_external_urls][@account_id]
				@cl_base = account_settings['cl_base_url']
				@key = account_settings['cl_integration_key']
				raise "Invalid Course Library client settings for account ID #{@account_id}" if @cl_base.blank? || @key.blank?
			end
		end

		def path_with_params(path, params)
			encoded_params = URI.encode_www_form(params)
			[path, encoded_params].join("?")
		end
	end
end