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

require File.expand_path(File.dirname(__FILE__) + '/../sharding_spec_helper')

require 'csv'

describe CourseCopyController do
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

  def upload_csv_file_import(file)
    data = Rack::Test::UploadedFile.new(file.path, 'text/csv', true)
    post 'create', account_id: @account, file: data
  end

  def check_create_response
    file = generate_file
    upload_csv_file_import(file)
    expect(response).to be_success
  end

  context "get index" do
    before(:once) { account_with_admin }
    before(:each) { user_session(@admin) }

    describe "GET 'index'" do
      it "should load index template" do
        account_with_admin_logged_in
        
        get 'index', account_id: @account
        expect(response).to be_success      
      end
    end
  end

  context "get history" do
    before(:once) { account_with_admin }
    before(:each) { user_session(@admin) }

    describe "GET 'history'" do
      it "should load history template" do
        account_with_admin_logged_in
        
        get 'history', account_id: @account
        expect(response).to be_success      
      end
    end
  end

  context "get progress" do
    before(:once) { account_with_admin }
    before(:each) { user_session(@admin) }

    describe "GET 'progress'" do
      it "should get progress data" do
        account_with_admin_logged_in
        
        get 'progress', account_id: @account, format: :json
        json = json_parse(response.body)
        expect(response).to be_success
        # expect(json).to have_key 'cm'   
      end
    end
  end  
  
end