#
# Copyright (C) 2012 Instructure, Inc.
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

module Api::V1::AccountAuthorizationConfig
  include Api::V1::Json

  def aacs_json(aacs)
    aacs.map do |aac|
      aac_json(aac)
    end
  end

  def aac_json(aac)
    result = api_json(aac, nil, nil, :only => [:id, :position])
    allowed_params = aac.class.recognized_params
    allowed_params.delete(:auth_password)
    allowed_params.each do |param|
      result[param] = aac.send(param)
    end

    # These settings were moved to the account settings level,
    # but we can't just change the API with no warning, so this keeps
    # them coming through in the JSON until we get appropriate notifications
    # sent and have given reasonable time to update any integrations.
    #  --2015-05-08
    aac.class.deprecated_params.each do |setting|
      result[setting] = aac.account.public_send(setting)
    end

    result
  end
end
