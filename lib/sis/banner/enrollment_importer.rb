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
    class EnrollmentImporter < BannerBaseImporter

      def self.is_enrollment_csv?(row)
        row.include?('external_course_key') && row.include?('external_person_key')
      end

      # expected columns
      # course_id,user_id,role,section_id,status
      def process(csv)
        messages = []
        @sis.counts[:enrollments] += SIS::EnrollmentImporter.new(@root_account, importer_opts).process(messages, @sis.updates_every) do |importer|
          csv_rows(csv) do |row|
            update_progress

            course_id = row['external_course_key']
            section_id = nil
            pseudonym = Pseudonym.find_by_unique_id(row['external_person_key'])
            messages << "User #{row['external_person_key']} didn't exist for user enrollment" unless pseudonym
            user_id = pseudonym ? pseudonym.sis_user_id : nil
            role = row['role'] || 'student'
            status = 'active'
            start_date = nil
            end_date = nil
            associated_user_id = user_id
            #begin
            #  start_date = DateTime.parse(row['start_date']) unless row['start_date'].blank?
            #  end_date = DateTime.parse(row['end_date']) unless row['end_date'].blank?
            #rescue
            #  messages << "Bad date format for user #{row['user_id']} in #{row['course_id'].blank? ? 'section' : 'course'} #{row['course_id'].blank? ? row['section_id'] : row['course_id']}"
            #end

            begin
              importer.add_enrollment(course_id, section_id, user_id, role, status, start_date, end_date, associated_user_id)
            rescue ImportError => e
              messages << "#{e}"
              next
            end
          end
        end
        messages.each { |message| add_warning(csv, message) }
      end
    end
  end
end
