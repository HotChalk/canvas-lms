#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class HotchalkPackageImportsController < ApplicationController

  def index
    plugin = Canvas::Plugin.find(:hotchalk)
    if plugin.enabled?
      begin
        account_settings = plugin.settings[:account_external_urls][params[:root_account_id]]
        base_url = account_settings['cl_base_url']
        integration_key = account_settings['cl_integration_key']
        raise "Invalid Hotchalk plugin settings for account ID #{params[:root_account_id]}" if base_url.blank? || integration_key.blank?
        uri = URI.parse("https://#{base_url}/clws/integration/packages")
        request = Net::HTTP::Get.new(uri.path)
        request.add_field("Shared-Key", integration_key) unless integration_key.blank?
        response = Net::HTTP.new(uri.host).start do |http|
          http.request(request)
        end
        render :json => response.body
      rescue => e
        logger.error "Unable to fetch Hotchalk package import list", e
        render(:json => { :message => t('invalid_account_external_urls', "Invalid Hotchalk plugin settings for this account") }, :status => :bad_request)
      end
    end
  end

end
