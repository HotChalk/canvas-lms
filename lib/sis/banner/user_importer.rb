#
# Copyright (C) 2013 Hotchalk, Inc.
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

module SIS
  module Banner
    class UserImporter < BannerBaseImporter

      def self.is_user_csv?(row)
        row.include?('user_id') && row.include?('student_id')
      end

      def process(csv)
        messages = []
        @sis.counts[:users] += SIS::UserImporter.new(@root_account, importer_opts).process(@sis.updates_every, messages) do |importer|
          csv_rows(csv) do |row|
            update_progress

            begin
              importer.add_user(row['student_id'], row['user_id'], 'active', row['firstname'], row['lastname'], row['email'], nil, nil)
            rescue ImportError => e
              messages << "#{e}"
            end
          end
        end
        messages.each { |message| add_warning(csv, message) }
      end
    end
  end
end
