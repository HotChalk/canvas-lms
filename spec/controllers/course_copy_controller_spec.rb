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

  describe "GET 'index'" do
    it "should throw 404 error without a valid context id" do
      get 'index'
      assert_status(404)
    end

    it "should return unauthorized without a valid session" do      
      get 'index', account_id: @account
      assert_unauthorized
    end

    it "should load index template" do
      account_with_admin_logged_in
      
      get 'index', account_id: @account
      expect(response).to be_success      
    end
  end

  describe "GET 'history'" do
    it "should throw 404 error without a valid context id" do
      get 'history'
      assert_status(404)
    end

    it "should return unauthorized without a valid session" do      
      get 'history', account_id: @account
      assert_unauthorized
    end

    it "should load index template" do
      account_with_admin_logged_in
      
      get 'history', account_id: @account
      expect(response).to be_success      
    end
  end

  describe "GET 'progress'" do
    it "should throw 404 error without a valid context id" do
      get 'progress', format: :json
      assert_status(404)
    end

    it "should return unauthorized without a valid session" do      
      get 'progress', account_id: @account, format: :json
      assert_unauthorized
    end

    it "should load index template" do
      account_with_admin_logged_in
      
      get 'progress', account_id: @account, format: :json
      json = json_parse(response.body)
      expect(response).to be_success
      expect(json).to have_key 'cm'      
    end
  end

  describe "POST 'create'" do
    it "should require authorization" do      
      post 'create', account_id: @account
      assert_unauthorized
    end

    it 'must have a file selected' do
      post 'create', account_id: @account
      expect(assigns[:file]).not_to be_nil      
      expect(flash[:error]).not_to be_nil
    end

    it "should accept a valid csv upload" do
      check_create_response
    end

  end

end