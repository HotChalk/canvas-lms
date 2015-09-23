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

module Api::V1::Context

  def context_data(obj)
    if obj.context_type.present?
      context_type = obj.context_type
      id = obj.context_id
      if(context_type == 'AssignmentOverride')
        title = obj.context.title
      else
        name = obj.context.name
      end
      if(context_type == 'Course')
        code = (obj.respond_to?(:data) && obj.data.respond_to?(:context_short_name)) ? obj.data.context_short_name : nil
      end
    elsif (obj.respond_to?(:context_code) || obj.is_a?(OpenObject)) && obj.context_code.present?
      context_type, id = obj.context_code.split("_", 2)
    else
      return {}
    end
    hash = {
      'context_type' => context_type.camelcase,
      "#{context_type.underscore}_id" => id.to_i
    }
    hash.merge!({ "#{context_type.underscore}_name" => name }) unless (context_type == 'AssignmentOverride')
    hash.merge!({ "#{context_type.underscore}_code" => code }) if(context_type == 'Course')
    hash.merge!({ "#{context_type.underscore}_title" => title }) if(context_type == 'AssignmentOverride')
    hash
  end

end

