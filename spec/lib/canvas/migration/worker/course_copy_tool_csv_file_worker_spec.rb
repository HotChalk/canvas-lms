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

require 'csv'

describe Canvas::Migration::Worker::CourseCopyToolCsvFileWorker do
  def account_with_admin_logged_in(opts = {})
    account_with_admin(opts)
    user_session(@admin)
  end

  def account_with_admin(opts = {})
    @account = opts[:account] || Account.default
    account_admin_user(account: @account)
  end

  def generate_file
    file = Tempfile.new("csv.csv")
    CSV.open(file, "wb") do |csv|
      csv << ["Master","Target"]
      csv << [4,5]
    end
    file.close    
    file
  end

  def generate_file_wrong_title
    file = Tempfile.new("csv.csv")
    CSV.open(file, "wb") do |csv|
      csv << ["M","T"]
      csv << [4,5]
    end
    file.close    
    file
  end  

  def generate_file_empty
    file = Tempfile.new("csv.csv")
    CSV.open(file, "wb") do |csv|
      csv << ["Master","Target"]      
    end
    file.close    
    file
  end  

  def upload_csv_file_import(file)    
      csv_data = Rack::Test::UploadedFile.new(file.path, 'text/csv', true)        
      @file_data = read_csv_file(csv_data)    
  end

  def create_csv_file(type)
    file = generate_file if type == 'clean'
    file = generate_file_wrong_title if type == 'wrong_title'
    file = generate_file_empty if type == 'empty'
    upload_csv_file_import(file)    
  end

  def read_csv_file(file)
    csv_table = CSV.table(file.path, {:headers => true, :header_converters => :symbol, :converters => :all})
    raise "CSV does not have any data to process" if csv_table.headers.length < 1
    raise "Incorrect CSV headers" unless csv_table.headers == [:master, :target]
    data_arr = csv_table.to_a.drop(1)
    raise "CSV does not have any data to process" unless data_arr.length > 0
    data_arr
  end

  def create_clean_migration
    course_with_teacher(:course_name => "from course", :active_all => true)
    @copy_from = @course
    
    @cm = ContentMigration.new(
      :context => @account,
      :user => @user,      
      :migration_type => 'course_copy_tool_csv_importer',
      initiated_source: :api
    )
    @cm.workflow_state = 'created'
    @cm.migration_settings[:import_immediately] = true
    @cm.migration_settings[:csv_data] = @file_data
    @cm.migration_settings[:due_dates] = 0
    @cm.migration_settings[:results] = []
    @cm.save!
  end
  
  context "create migration" do
    before(:once) { 
      account_with_admin
      create_csv_file('clean')
      create_clean_migration     
    }

    it "should create and process the migration" do    
      worker = Canvas::Migration::Worker::CourseCopyToolCsvFileWorker.new(@cm.id)
      expect(worker.perform()).to eq true
      expect(@cm.reload.migration_settings[:results]).not_to be_nil   
    end
  end

  context "read file with wrong data" do
    before(:once) { 
      account_with_admin      
    }

    it "reading file with wrong titles" do
      expect{create_csv_file('wrong_title')}.to raise_error("Incorrect CSV headers")      
    end

    it "reading file without any data to process" do
      expect{create_csv_file('empty')}.to raise_error("CSV does not have any data to process")      
    end
  end  
end
