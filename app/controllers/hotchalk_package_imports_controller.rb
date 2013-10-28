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
    if Canvas::Plugin.find(:hotchalk).enabled?
      base_url = PluginSetting.settings_for_plugin(:hotchalk)['cl_base_url']
      integration_key = PluginSetting.settings_for_plugin(:hotchalk)['cl_integration_key']
      uri = URI.parse("https://#{base_url}/clws/integration/packages")
      request = Net::HTTP::Get.new(uri.path)
      request.add_field("Shared-Key", integration_key) unless integration_key.blank?
      response = Net::HTTP.new(uri.host).start do |http|
        http.request(request)
      end
      render :json => response.body
    end
  end

end
