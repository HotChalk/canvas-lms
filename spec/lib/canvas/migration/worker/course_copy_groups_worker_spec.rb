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

require File.expand_path(File.dirname(__FILE__) + '/../../../../sharding_spec_helper')

require_dependency 'importers'

describe Canvas::Migration::Worker::CourseCopyGroupsWorker do  
  context "create migration" do
    
    it "should copy groups from a course to another" do
      source = course_model
      group_category = source.group_categories.create(:name => "worldCup")
      group1 = Group.create!(:name=>"group1", :group_category => group_category, :context => source)
      target = course_model
      migration = target.content_migrations.create!
      groups = source.groups.active
      group_categories = source.group_categories.active
      data = {
          :groups => groups || [],
          :group_categories => group_categories || []
      }
      Importers::GroupImporter.import_groups_extra(data, migration)
      new_group = Group.where(migration_id: data[:migration_id]).first
      expect(new_group).not_to be_nil
    end
  end  
end
