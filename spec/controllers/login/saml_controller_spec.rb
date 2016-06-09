#
# Copyright (C) 2011 - 2015 Instructure, Inc.
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

require_relative '../../spec_helper'

describe Login::SamlController do
  before do
    skip("requires SAML extension") unless AccountAuthorizationConfig::SAML.enabled?
  end

  it "should scope logins to the correct domain root account" do
    unique_id = 'foo@example.com'

    account1 = account_with_saml
    user1 = user_with_pseudonym({:active_all => true, :username => unique_id})
    @pseudonym.account = account1
    @pseudonym.save!

    account2 = account_with_saml
    user2 = user_with_pseudonym({:active_all => true, :username => unique_id})
    @pseudonym.account = account2
    @pseudonym.save!

    Onelogin::Saml::Response.stubs(:new).returns(
      stub('response',
           is_valid?: true,
           success_status?: true,
           name_id: unique_id,
           name_qualifier: nil,
           session_index: nil,
           process: nil,
           issuer: "saml_entity"
          )
    )

    controller.request.env['canvas.domain_root_account'] = account1
    session[:sentinel] = true
    post :create, :SAMLResponse => "foo"
    expect(session[:sentinel]).to be_nil
    expect(response).to redirect_to(dashboard_url(:login_success => 1))
    expect(session[:saml_unique_id]).to eq unique_id
    expect(Pseudonym.find(session['pseudonym_credentials_id'])).to eq user1.pseudonyms.first

    (controller.instance_variables.grep(/@[^_]/) - ['@mock_proxy']).each do |var|
      controller.send :remove_instance_variable, var
    end
    session.clear

    controller.request.env['canvas.domain_root_account'] = account2
    post :create, :SAMLResponse => "bar"
    expect(response).to redirect_to(dashboard_url(:login_success => 1))
    expect(session[:saml_unique_id]).to eq unique_id
    expect(Pseudonym.find(session['pseudonym_credentials_id'])).to eq user2.pseudonyms.first
  end

  it "does not enforce a valid entity id" do
    unique_id = 'foo@example.com'

    account1 = account_with_saml
    user1 = user_with_pseudonym({:active_all => true, :username => unique_id})
    @pseudonym.account = account1
    @pseudonym.save!

    Onelogin::Saml::Response.stubs(:new).returns(
        stub('response',
             is_valid?: true,
             success_status?: true,
             name_id: unique_id,
             name_qualifier: nil,
             session_index: nil,
             process: nil,
             issuer: "such a lie"
        )
    )

    controller.request.env['canvas.domain_root_account'] = account1
    post :create, :SAMLResponse => "foo"
    expect(response).to redirect_to(dashboard_url(:login_success => 1))
    expect(session[:saml_unique_id]).to eq unique_id
    expect(Pseudonym.find(session['pseudonym_credentials_id'])).to eq user1.pseudonyms.first
  end

  it "should redirect when a user is authenticated but is not found in canvas" do
    unique_id = 'foo@example.com'

    account = account_with_saml

    Onelogin::Saml::Response.stubs(:new).returns(
      stub('response',
           is_valid?: true,
           success_status?: true,
           name_id: unique_id,
           name_qualifier: nil,
           session_index: nil,
           process: nil,
           issuer: "saml_entity"
          )
    )

    # We dont want to log them out of everything.
    controller.expects(:logout_user_action).never
    controller.request.env['canvas.domain_root_account'] = account

    # Default to Login url if set to nil or blank
    post :create, :SAMLResponse => "foo"
    expect(response).to redirect_to(login_url)
    expect(flash[:delegated_message]).to_not be_nil
    expect(session[:saml_unique_id]).to be_nil

    account.unknown_user_url = ''
    account.save!
    controller.instance_variable_set(:@aac, nil)
    post :create, :SAMLResponse => "foo"
    expect(response).to redirect_to(login_url)
    expect(flash[:delegated_message]).to_not be_nil
    expect(session[:saml_unique_id]).to be_nil

    # Redirect to a specifiec url
    unknown_user_url = "https://example.com/unknown_user"
    account.unknown_user_url = unknown_user_url
    account.save!
    controller.instance_variable_set(:@aac, nil)
    post :create, :SAMLResponse => "foo"
    expect(response).to redirect_to(unknown_user_url)
    expect(session[:saml_unique_id]).to be_nil
  end

  it "creates an unfound user when JIT provisioning is enabled" do
    unique_id = 'foo@example.com'

    account = account_with_saml
    ap = account.authentication_providers.first
    ap.update_attribute(:jit_provisioning, true)

    Onelogin::Saml::Response.stubs(:new).returns(
      stub('response',
           is_valid?: true,
           success_status?: true,
           name_id: unique_id,
           name_qualifier: nil,
           session_index: nil,
           process: nil,
           issuer: "saml_entity"
          ))

    # We dont want to log them out of everything.
    controller.expects(:logout_user_action).never
    controller.request.env['canvas.domain_root_account'] = account

    expect(account.pseudonyms.active.by_unique_id(unique_id)).to_not be_exists
    # Default to Login url if set to nil or blank
    post :create, :SAMLResponse => "foo"
    expect(response).to redirect_to(dashboard_url(login_success: 1))
    p = account.pseudonyms.active.by_unique_id(unique_id).first!
    expect(p.authentication_provider).to eq ap
  end

  context "multiple authorization configs" do
    before :once do
      @account = Account.create!
      @unique_id = 'foo@example.com'
      @user1 = user_with_pseudonym(:active_all => true, :username => @unique_id, :account => @account)
      @account.authentication_providers.create!(:auth_type => 'saml', :identifier_format => 'uid')

      @aac2 = @account.authentication_providers.build(auth_type: 'saml')
      @aac2.idp_entity_id = "https://example.com/idp1"
      @aac2.log_out_url = "https://example.com/idp1/slo"
      @aac2.save!

      @stub_hash = {
          :issuer => @aac2.idp_entity_id,
          :is_valid? => true,
          :success_status? => true,
          :name_id => @unique_id,
          :name_qualifier => nil,
          :session_index => nil,
          :process => nil,
      }
    end

    it "should saml_consume login with multiple authorization configs" do
      Onelogin::Saml::Response.stubs(:new).returns(stub('response', @stub_hash))
      controller.request.env['canvas.domain_root_account'] = @account
      post :create, :SAMLResponse => "foo", :RelayState => "/courses"
      expect(response).to redirect_to(courses_url)
      expect(session[:saml_unique_id]).to eq @unique_id
    end

    it "should saml_logout with multiple authorization configs" do
      Onelogin::Saml::LogoutResponse.stubs(:parse).returns(
        stub('response', @stub_hash)
      )
      controller.request.env['canvas.domain_root_account'] = @account
      get :destroy, :SAMLResponse => "foo", :RelayState => "/courses"

      expect(response).to redirect_to(saml_login_url(@aac2))
    end
  end

  context "multiple SAML configs" do
    before :once do
      @account = account_with_saml(:saml_log_in_url => "https://example.com/idp1/sli")
      @unique_id = 'foo@example.com'
      @user1 = user_with_pseudonym(:active_all => true, :username => @unique_id, :account => @account)
      @aac1 = @account.authentication_providers.first
      @aac1.idp_entity_id = "https://example.com/idp1"
      @aac1.log_out_url = "https://example.com/idp1/slo"
      @aac1.save!

      @aac2 = @aac1.clone
      @aac2.idp_entity_id = "https://example.com/idp2"
      @aac2.log_in_url = "https://example.com/idp2/sli"
      @aac2.log_out_url = "https://example.com/idp2/slo"
      @aac2.position = nil
      @aac2.save!

      @stub_hash = {
        issuer: @aac2.idp_entity_id,
        is_valid?: true,
        success_status?: true,
        name_id: @unique_id,
        name_qualifier: nil,
        session_index: nil,
        process: nil
      }
    end

    context "#create" do
      def post_create
        Onelogin::Saml::Response.stubs(:new).returns(
          stub('response', @stub_hash)
        )
        controller.request.env['canvas.domain_root_account'] = @account
        post :create, :SAMLResponse => "foo", :RelayState => "/courses"
      end

      it "finds the SAML config by entity_id" do
        @aac1.any_instantiation.expects(:saml_settings).never
        @aac2.any_instantiation.expects(:saml_settings)

        post_create

        expect(response).to redirect_to(courses_url)
        expect(session[:saml_unique_id]).to eq @unique_id
      end

      it "redirects to login screen with message if no AAC found" do
        @stub_hash[:issuer] = "hahahahahahaha"

        session[:sentinel] = true
        post_create
        expect(session[:sentinel]).to eq true

        expect(response).to redirect_to(login_url)
        expect(flash[:delegated_message]).to eq "The institution you logged in from is not configured on this account."
      end
    end

    context "/new" do
      def get_new(aac_id=nil)
        controller.request.env['canvas.domain_root_account'] = @account
        if aac_id
          get 'new', id: aac_id
        else
          get 'new'
        end
      end

      it "should redirect to default login" do
        get_new
        expect(response.location.starts_with?(controller.delegated_auth_redirect_uri(@aac1.log_in_url))).to be_truthy
      end

      it "should use the specified AAC" do
        get_new("#{@aac1.id}")
        expect(response.location.starts_with?(controller.delegated_auth_redirect_uri(@aac1.log_in_url))).to be_truthy
        controller.instance_variable_set(:@aac, nil)
        get_new("#{@aac2.id}")
        expect(response.location.starts_with?(controller.delegated_auth_redirect_uri(@aac2.log_in_url))).to be_truthy
      end

      it "reject  unknown specified AAC" do
        get_new("0")
        expect(response.status).to eq 404
      end
    end

    context "logging out" do
      before do
        Onelogin::Saml::Response.stubs(:new).returns(
          stub('response', @stub_hash)
        )
        controller.request.env['canvas.domain_root_account'] = @account
        post :create, :SAMLResponse => "foo", :RelayState => "/courses"

        expect(response).to redirect_to(courses_url)
        expect(session[:saml_unique_id]).to eq @unique_id
        expect(session[:login_aac]).to eq @aac2.id
      end

      describe '#destroy' do
        it "should return bad request if a SAMLResponse or SAMLRequest parameter is not provided" do
          controller.expects(:logout_user_action).never
          get :destroy
          expect(response.status).to eq 400
        end

        it "should find the correct AAC" do
          @aac1.any_instantiation.expects(:saml_settings).never
          @aac2.any_instantiation.expects(:saml_settings).at_least_once

          Onelogin::Saml::LogoutResponse.stubs(:parse).returns(
            stub('response', @stub_hash)
          )

          controller.request.env['canvas.domain_root_account'] = @account
          get :destroy, :SAMLResponse => "foo"
          expect(response).to redirect_to(saml_login_url(@aac2))
        end

        it "should redirect a response to idp on logout with a SAMLRequest parameter" do
          controller.expects(:logout_current_user)
          @stub_hash[:id] = '_42'

          Onelogin::Saml::LogoutRequest.stubs(:parse).returns(
            stub('request', @stub_hash)
          )

          controller.request.env['canvas.domain_root_account'] = @account
          get :destroy, :SAMLRequest => "foo"

          expect(response).to be_redirect
          expect(response.location).to match %r{^https://example.com/idp2/slo\?SAMLResponse=}
        end

        it "returns bad request if SAMLRequest parameter doesn't match an AAC" do
          @stub_hash[:id] = '_42'
          @stub_hash[:issuer] = "hahahahahahaha"
          Onelogin::Saml::LogoutRequest.stubs(:parse).returns(
            stub('request', @stub_hash)
          )

          controller.request.env['canvas.domain_root_account'] = @account
          get :destroy, :SAMLRequest => "foo"

          expect(response.status).to eq 400
        end
      end
    end
  end

  context "/saml_logout" do
    it "should return bad request if SAML is not configured for account" do
      Onelogin::Saml::LogoutResponse.expects(:parse).returns(
        stub('response', issuer: 'entity')
      )

      controller.expects(:logout_user_action).never
      controller.request.env['canvas.domain_root_account'] = @account
      get :destroy, :SAMLResponse => "foo", :RelayState => "/courses"
      expect(response.status).to eq 400
    end
  end

  context "login attributes" do
    before :once do
      @unique_id = 'foo'

      @account = account_with_saml
      @user = user_with_pseudonym({:active_all => true, :username => @unique_id})
      @pseudonym.account = @account
      @pseudonym.save!

      @aac = @account.authentication_providers.first
    end

    it "should use the eduPersonPrincipalName attribute with the domain stripped" do
      @aac.login_attribute = 'eduPersonPrincipalName_stripped'
      @aac.save

      Onelogin::Saml::Response.stubs(:new).returns(
        stub('response',
             is_valid?: true,
             success_status?: true,
             name_id: nil,
             name_qualifier: nil,
             session_index: nil,
             process: nil,
             issuer: "saml_entity",
             saml_attributes: {
                 'eduPersonPrincipalName' => "#{@unique_id}@example.edu"
             }
            )
      )

      controller.request.env['canvas.domain_root_account'] = @account
      post :create, :SAMLResponse => "foo", :RelayState => "/courses"
      expect(response).to redirect_to(courses_url)
      expect(session[:saml_unique_id]).to eq @unique_id
    end

    it "should use the NameID if no login attribute is specified" do
      @aac.login_attribute = nil
      @aac.save

      Onelogin::Saml::Response.stubs(:new).returns(
        stub('response',
             is_valid?: true,
             success_status?: true,
             name_id: @unique_id,
             name_qualifier: nil,
             session_index: nil,
             process: nil,
             issuer: "saml_entity"
            )
      )

      controller.request.env['canvas.domain_root_account'] = @account
      post :create, :SAMLResponse => "foo", :RelayState => "/courses"
      expect(response).to redirect_to(courses_url)
      expect(session[:saml_unique_id]).to eq @unique_id
    end
  end

  it "should use the eppn saml attribute if configured" do
    unique_id = 'foo'

    account = account_with_saml
    @aac = @account.authentication_providers.first
    @aac.login_attribute = 'eduPersonPrincipalName_stripped'
    @aac.save

    user_with_pseudonym({:active_all => true, :username => unique_id})
    @pseudonym.account = account
    @pseudonym.save!

    Onelogin::Saml::Response.stubs(:new).returns(
      stub('response',
           is_valid?: true,
           success_status?: true,
           name_id: nil,
           name_qualifier: nil,
           session_index: nil,
           process: nil,
           issuer: "saml_entity",
           saml_attributes: {
             'eduPersonPrincipalName' => "#{unique_id}@example.edu"
           }
          )
    )

    controller.request.env['canvas.domain_root_account'] = account
    post :create, :SAMLResponse => "foo", :RelayState => "/courses"
    expect(response).to redirect_to(courses_url)
    expect(session[:saml_unique_id]).to eq unique_id
  end

  it "should redirect to RelayState relative urls" do
    unique_id = 'foo@example.com'

    account = account_with_saml
    user_with_pseudonym({:active_all => true, :username => unique_id})
    @pseudonym.account = account
    @pseudonym.save!

    Onelogin::Saml::Response.stubs(:new).returns(
      stub('response',
           is_valid?: true,
           success_status?: true,
           name_id: unique_id,
           name_qualifier: nil,
           session_index: nil,
           process: nil,
           issuer: "saml_entity"
          )
    )

    controller.request.env['canvas.domain_root_account'] = account
    post :create, :SAMLResponse => "foo", :RelayState => "/courses"
    expect(response).to redirect_to(courses_url)
    expect(session[:saml_unique_id]).to eq unique_id
  end

  it "should decode an actual saml response" do
    unique_id = 'student@example.edu'

    account_with_saml

    @aac = @account.authentication_providers.first
    @aac.idp_entity_id = 'http://phpsite/simplesaml/saml2/idp/metadata.php'
    @aac.login_attribute = 'eduPersonPrincipalName'
    @aac.certificate_fingerprint = 'AF:E7:1C:28:EF:74:0B:C8:74:25:BE:13:A2:26:3D:37:97:1D:A1:F9'
    @aac.save

    user_with_pseudonym(:active_all => true, :username => unique_id)
    @pseudonym.account = @account
    @pseudonym.save!

    controller.request.env['canvas.domain_root_account'] = @account
    post :create, :SAMLResponse => <<-SAML
        PHNhbWxwOlJlc3BvbnNlIHhtbG5zOnNhbWxwPSJ1cm46b2FzaXM6bmFtZXM6dGM6U0FNTDoyLjA6cHJv
        dG9jb2wiIHhtbG5zOnNhbWw9InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDphc3NlcnRpb24iIElE
        PSJfMzJmMTBlOGU0NjVmY2VmNzIzNjhlMjIwZmFlYjgxZGI0YzcyZjBjNjg3IiBWZXJzaW9uPSIyLjAi
        IElzc3VlSW5zdGFudD0iMjAxMi0wOC0wM1QyMDowNzoxNVoiIERlc3RpbmF0aW9uPSJodHRwOi8vc2hh
        cmQxLmxvY2FsZG9tYWluOjMwMDAvc2FtbF9jb25zdW1lIiBJblJlc3BvbnNlVG89ImQwMDE2ZWM4NThk
        OTIzNjBjNTk3YTAxZDE1NTk0NGY4ZGY4ZmRiMTE2ZCI+PHNhbWw6SXNzdWVyPmh0dHA6Ly9waHBzaXRl
        L3NpbXBsZXNhbWwvc2FtbDIvaWRwL21ldGFkYXRhLnBocDwvc2FtbDpJc3N1ZXI+PGRzOlNpZ25hdHVy
        ZSB4bWxuczpkcz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC8wOS94bWxkc2lnIyI+CiAgPGRzOlNpZ25l
        ZEluZm8+PGRzOkNhbm9uaWNhbGl6YXRpb25NZXRob2QgQWxnb3JpdGhtPSJodHRwOi8vd3d3LnczLm9y
        Zy8yMDAxLzEwL3htbC1leGMtYzE0biMiLz4KICAgIDxkczpTaWduYXR1cmVNZXRob2QgQWxnb3JpdGht
        PSJodHRwOi8vd3d3LnczLm9yZy8yMDAwLzA5L3htbGRzaWcjcnNhLXNoYTEiLz4KICA8ZHM6UmVmZXJl
        bmNlIFVSST0iI18zMmYxMGU4ZTQ2NWZjZWY3MjM2OGUyMjBmYWViODFkYjRjNzJmMGM2ODciPjxkczpU
        cmFuc2Zvcm1zPjxkczpUcmFuc2Zvcm0gQWxnb3JpdGhtPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwLzA5
        L3htbGRzaWcjZW52ZWxvcGVkLXNpZ25hdHVyZSIvPjxkczpUcmFuc2Zvcm0gQWxnb3JpdGhtPSJodHRw
        Oi8vd3d3LnczLm9yZy8yMDAxLzEwL3htbC1leGMtYzE0biMiLz48L2RzOlRyYW5zZm9ybXM+PGRzOkRp
        Z2VzdE1ldGhvZCBBbGdvcml0aG09Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvMDkveG1sZHNpZyNzaGEx
        Ii8+PGRzOkRpZ2VzdFZhbHVlPlM2TmUxMW5CN2cxT3lRQUdZckZFT251NVFBUT08L2RzOkRpZ2VzdFZh
        bHVlPjwvZHM6UmVmZXJlbmNlPjwvZHM6U2lnbmVkSW5mbz48ZHM6U2lnbmF0dXJlVmFsdWU+bWdxWlVp
        QTNtYXRyajZaeTREbCsxZ2hzZ29PbDh3UEgybXJGTTlQQXFyWUIwc2t1SlVaaFlVa0NlZ0ViRVg5V1JP
        RWhvWjJiZ3dKUXFlVVB5WDdsZU1QZTdTU2RVRE5LZjlraXV2cGNDWVpzMWxGU0VkNTFFYzhmK0h2ZWpt
        SFVKQVUrSklSV3BwMVZrWVVaQVRpaHdqR0xvazNOR2kveWdvYWpOaDQydlo0PTwvZHM6U2lnbmF0dXJl
        VmFsdWU+CjxkczpLZXlJbmZvPjxkczpYNTA5RGF0YT48ZHM6WDUwOUNlcnRpZmljYXRlPk1JSUNnVEND
        QWVvQ0NRQ2JPbHJXRGRYN0ZUQU5CZ2txaGtpRzl3MEJBUVVGQURDQmhERUxNQWtHQTFVRUJoTUNUazh4
        R0RBV0JnTlZCQWdURDBGdVpISmxZWE1nVTI5c1ltVnlaekVNTUFvR0ExVUVCeE1EUm05dk1SQXdEZ1lE
        VlFRS0V3ZFZUa2xPUlZSVU1SZ3dGZ1lEVlFRREV3OW1aV2xrWlM1bGNteGhibWN1Ym04eElUQWZCZ2tx
        aGtpRzl3MEJDUUVXRW1GdVpISmxZWE5BZFc1cGJtVjBkQzV1YnpBZUZ3MHdOekEyTVRVeE1qQXhNelZh
        Rncwd056QTRNVFF4TWpBeE16VmFNSUdFTVFzd0NRWURWUVFHRXdKT1R6RVlNQllHQTFVRUNCTVBRVzVr
        Y21WaGN5QlRiMnhpWlhKbk1Rd3dDZ1lEVlFRSEV3TkdiMjh4RURBT0JnTlZCQW9UQjFWT1NVNUZWRlF4
        R0RBV0JnTlZCQU1URDJabGFXUmxMbVZ5YkdGdVp5NXViekVoTUI4R0NTcUdTSWIzRFFFSkFSWVNZVzVr
        Y21WaGMwQjFibWx1WlhSMExtNXZNSUdmTUEwR0NTcUdTSWIzRFFFQkFRVUFBNEdOQURDQmlRS0JnUURp
        dmJoUjdQNTE2eC9TM0JxS3h1cFFlMExPTm9saXVwaUJPZXNDTzNTSGJEcmwzK3E5SWJmbmZtRTA0ck51
        TWNQc0l4QjE2MVRkRHBJZXNMQ243YzhhUEhJU0tPdFBsQWVUWlNuYjhRQXU3YVJqWnEzK1BiclA1dVcz
        VGNmQ0dQdEtUeXRIT2dlL09sSmJvMDc4ZFZoWFExNGQxRUR3WEpXMXJSWHVVdDRDOFFJREFRQUJNQTBH
        Q1NxR1NJYjNEUUVCQlFVQUE0R0JBQ0RWZnA4NkhPYnFZK2U4QlVvV1E5K1ZNUXgxQVNEb2hCandPc2cy
        V3lrVXFSWEYrZExmY1VIOWRXUjYzQ3RaSUtGRGJTdE5vbVBuUXo3bmJLK29ueWd3QnNwVkVibkh1VWlo
        WnEzWlVkbXVtUXFDdzRVdnMvMVV2cTNvck9vL1dKVmhUeXZMZ0ZWSzJRYXJRNC82N09aZkhkN1IrUE9C
        WGhvcGhTTXYxWk9vPC9kczpYNTA5Q2VydGlmaWNhdGU+PC9kczpYNTA5RGF0YT48L2RzOktleUluZm8+
        PC9kczpTaWduYXR1cmU+PHNhbWxwOlN0YXR1cz48c2FtbHA6U3RhdHVzQ29kZSBWYWx1ZT0idXJuOm9h
        c2lzOm5hbWVzOnRjOlNBTUw6Mi4wOnN0YXR1czpTdWNjZXNzIi8+PC9zYW1scDpTdGF0dXM+PHNhbWw6
        QXNzZXJ0aW9uIHhtbG5zOnhzaT0iaHR0cDovL3d3dy53My5vcmcvMjAwMS9YTUxTY2hlbWEtaW5zdGFu
        Y2UiIHhtbG5zOnhzPSJodHRwOi8vd3d3LnczLm9yZy8yMDAxL1hNTFNjaGVtYSIgSUQ9Il82MjEyYjdl
        OGMwNjlkMGY5NDhjODY0ODk5MWQzNTdhZGRjNDA5NWE4MmYiIFZlcnNpb249IjIuMCIgSXNzdWVJbnN0
        YW50PSIyMDEyLTA4LTAzVDIwOjA3OjE1WiI+PHNhbWw6SXNzdWVyPmh0dHA6Ly9waHBzaXRlL3NpbXBs
        ZXNhbWwvc2FtbDIvaWRwL21ldGFkYXRhLnBocDwvc2FtbDpJc3N1ZXI+PGRzOlNpZ25hdHVyZSB4bWxu
        czpkcz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC8wOS94bWxkc2lnIyI+CiAgPGRzOlNpZ25lZEluZm8+
        PGRzOkNhbm9uaWNhbGl6YXRpb25NZXRob2QgQWxnb3JpdGhtPSJodHRwOi8vd3d3LnczLm9yZy8yMDAx
        LzEwL3htbC1leGMtYzE0biMiLz4KICAgIDxkczpTaWduYXR1cmVNZXRob2QgQWxnb3JpdGhtPSJodHRw
        Oi8vd3d3LnczLm9yZy8yMDAwLzA5L3htbGRzaWcjcnNhLXNoYTEiLz4KICA8ZHM6UmVmZXJlbmNlIFVS
        ST0iI182MjEyYjdlOGMwNjlkMGY5NDhjODY0ODk5MWQzNTdhZGRjNDA5NWE4MmYiPjxkczpUcmFuc2Zv
        cm1zPjxkczpUcmFuc2Zvcm0gQWxnb3JpdGhtPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwLzA5L3htbGRz
        aWcjZW52ZWxvcGVkLXNpZ25hdHVyZSIvPjxkczpUcmFuc2Zvcm0gQWxnb3JpdGhtPSJodHRwOi8vd3d3
        LnczLm9yZy8yMDAxLzEwL3htbC1leGMtYzE0biMiLz48L2RzOlRyYW5zZm9ybXM+PGRzOkRpZ2VzdE1l
        dGhvZCBBbGdvcml0aG09Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvMDkveG1sZHNpZyNzaGExIi8+PGRz
        OkRpZ2VzdFZhbHVlPmthWk4xK21vUzMyOHByMnpuOFNLVU1MMUVsST08L2RzOkRpZ2VzdFZhbHVlPjwv
        ZHM6UmVmZXJlbmNlPjwvZHM6U2lnbmVkSW5mbz48ZHM6U2lnbmF0dXJlVmFsdWU+MWtVRWtHMzNaR1FN
        Zi8xSDFnenFCT2hUNU4ySTM1dk0wNEpwNjd4VmpuWlhGNTRBcVBxMVphTStXamd4KytBakViTDdrc2FZ
        dU0zSlN5SzdHbFo3N1ZtenBMc01xbjRlTTAwSzdZK0NlWnk1TEIyNHZjbmdYUHhCazZCZFVZa1ZrMHZP
        c1VmQUFaK21SWC96ekJXN1o0QzdxYmpOR2hBQUpnaTEzSm9CV3BVPTwvZHM6U2lnbmF0dXJlVmFsdWU+
        CjxkczpLZXlJbmZvPjxkczpYNTA5RGF0YT48ZHM6WDUwOUNlcnRpZmljYXRlPk1JSUNnVENDQWVvQ0NR
        Q2JPbHJXRGRYN0ZUQU5CZ2txaGtpRzl3MEJBUVVGQURDQmhERUxNQWtHQTFVRUJoTUNUazh4R0RBV0Jn
        TlZCQWdURDBGdVpISmxZWE1nVTI5c1ltVnlaekVNTUFvR0ExVUVCeE1EUm05dk1SQXdEZ1lEVlFRS0V3
        ZFZUa2xPUlZSVU1SZ3dGZ1lEVlFRREV3OW1aV2xrWlM1bGNteGhibWN1Ym04eElUQWZCZ2txaGtpRzl3
        MEJDUUVXRW1GdVpISmxZWE5BZFc1cGJtVjBkQzV1YnpBZUZ3MHdOekEyTVRVeE1qQXhNelZhRncwd056
        QTRNVFF4TWpBeE16VmFNSUdFTVFzd0NRWURWUVFHRXdKT1R6RVlNQllHQTFVRUNCTVBRVzVrY21WaGN5
        QlRiMnhpWlhKbk1Rd3dDZ1lEVlFRSEV3TkdiMjh4RURBT0JnTlZCQW9UQjFWT1NVNUZWRlF4R0RBV0Jn
        TlZCQU1URDJabGFXUmxMbVZ5YkdGdVp5NXViekVoTUI4R0NTcUdTSWIzRFFFSkFSWVNZVzVrY21WaGMw
        QjFibWx1WlhSMExtNXZNSUdmTUEwR0NTcUdTSWIzRFFFQkFRVUFBNEdOQURDQmlRS0JnUURpdmJoUjdQ
        NTE2eC9TM0JxS3h1cFFlMExPTm9saXVwaUJPZXNDTzNTSGJEcmwzK3E5SWJmbmZtRTA0ck51TWNQc0l4
        QjE2MVRkRHBJZXNMQ243YzhhUEhJU0tPdFBsQWVUWlNuYjhRQXU3YVJqWnEzK1BiclA1dVczVGNmQ0dQ
        dEtUeXRIT2dlL09sSmJvMDc4ZFZoWFExNGQxRUR3WEpXMXJSWHVVdDRDOFFJREFRQUJNQTBHQ1NxR1NJ
        YjNEUUVCQlFVQUE0R0JBQ0RWZnA4NkhPYnFZK2U4QlVvV1E5K1ZNUXgxQVNEb2hCandPc2cyV3lrVXFS
        WEYrZExmY1VIOWRXUjYzQ3RaSUtGRGJTdE5vbVBuUXo3bmJLK29ueWd3QnNwVkVibkh1VWloWnEzWlVk
        bXVtUXFDdzRVdnMvMVV2cTNvck9vL1dKVmhUeXZMZ0ZWSzJRYXJRNC82N09aZkhkN1IrUE9CWGhvcGhT
        TXYxWk9vPC9kczpYNTA5Q2VydGlmaWNhdGU+PC9kczpYNTA5RGF0YT48L2RzOktleUluZm8+PC9kczpT
        aWduYXR1cmU+PHNhbWw6U3ViamVjdD48c2FtbDpOYW1lSUQgU1BOYW1lUXVhbGlmaWVyPSJodHRwOi8v
        c2hhcmQxLmxvY2FsZG9tYWluL3NhbWwyIiBGb3JtYXQ9InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIu
        MDpuYW1laWQtZm9ybWF0OnRyYW5zaWVudCI+XzNiM2U3NzE0YjcyZTI5ZGM0MjkwMzIxYTA3NWZhMGI3
        MzMzM2E0ZjI1Zjwvc2FtbDpOYW1lSUQ+PHNhbWw6U3ViamVjdENvbmZpcm1hdGlvbiBNZXRob2Q9InVy
        bjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDpjbTpiZWFyZXIiPjxzYW1sOlN1YmplY3RDb25maXJtYXRp
        b25EYXRhIE5vdE9uT3JBZnRlcj0iMjAxMi0wOC0wM1QyMDoxMjoxNVoiIFJlY2lwaWVudD0iaHR0cDov
        L3NoYXJkMS5sb2NhbGRvbWFpbjozMDAwL3NhbWxfY29uc3VtZSIgSW5SZXNwb25zZVRvPSJkMDAxNmVj
        ODU4ZDkyMzYwYzU5N2EwMWQxNTU5NDRmOGRmOGZkYjExNmQiLz48L3NhbWw6U3ViamVjdENvbmZpcm1h
        dGlvbj48L3NhbWw6U3ViamVjdD48c2FtbDpDb25kaXRpb25zIE5vdEJlZm9yZT0iMjAxMi0wOC0wM1Qy
        MDowNjo0NVoiIE5vdE9uT3JBZnRlcj0iMjAxMi0wOC0wM1QyMDoxMjoxNVoiPjxzYW1sOkF1ZGllbmNl
        UmVzdHJpY3Rpb24+PHNhbWw6QXVkaWVuY2U+aHR0cDovL3NoYXJkMS5sb2NhbGRvbWFpbi9zYW1sMjwv
        c2FtbDpBdWRpZW5jZT48L3NhbWw6QXVkaWVuY2VSZXN0cmljdGlvbj48L3NhbWw6Q29uZGl0aW9ucz48
        c2FtbDpBdXRoblN0YXRlbWVudCBBdXRobkluc3RhbnQ9IjIwMTItMDgtMDNUMjA6MDc6MTVaIiBTZXNz
        aW9uTm90T25PckFmdGVyPSIyMDEyLTA4LTA0VDA0OjA3OjE1WiIgU2Vzc2lvbkluZGV4PSJfMDJmMjZh
        ZjMwYTM3YWZiOTIwODFmM2E3MzcyODgxMDE5M2VmZDdmYTZlIj48c2FtbDpBdXRobkNvbnRleHQ+PHNh
        bWw6QXV0aG5Db250ZXh0Q2xhc3NSZWY+dXJuOm9hc2lzOm5hbWVzOnRjOlNBTUw6Mi4wOmFjOmNsYXNz
        ZXM6UGFzc3dvcmQ8L3NhbWw6QXV0aG5Db250ZXh0Q2xhc3NSZWY+PC9zYW1sOkF1dGhuQ29udGV4dD48
        L3NhbWw6QXV0aG5TdGF0ZW1lbnQ+PHNhbWw6QXR0cmlidXRlU3RhdGVtZW50PjxzYW1sOkF0dHJpYnV0
        ZSBOYW1lPSJ1cm46b2lkOjEuMy42LjEuNC4xLjU5MjMuMS4xLjEuMSIgTmFtZUZvcm1hdD0idXJuOm9h
        c2lzOm5hbWVzOnRjOlNBTUw6Mi4wOmF0dHJuYW1lLWZvcm1hdDp1cmkiPjxzYW1sOkF0dHJpYnV0ZVZh
        bHVlIHhzaTp0eXBlPSJ4czpzdHJpbmciPm1lbWJlcjwvc2FtbDpBdHRyaWJ1dGVWYWx1ZT48L3NhbWw6
        QXR0cmlidXRlPjxzYW1sOkF0dHJpYnV0ZSBOYW1lPSJ1cm46b2lkOjEuMy42LjEuNC4xLjU5MjMuMS4x
        LjEuNiIgTmFtZUZvcm1hdD0idXJuOm9hc2lzOm5hbWVzOnRjOlNBTUw6Mi4wOmF0dHJuYW1lLWZvcm1h
        dDp1cmkiPjxzYW1sOkF0dHJpYnV0ZVZhbHVlIHhzaTp0eXBlPSJ4czpzdHJpbmciPnN0dWRlbnRAZXhh
        bXBsZS5lZHU8L3NhbWw6QXR0cmlidXRlVmFsdWU+PC9zYW1sOkF0dHJpYnV0ZT48L3NhbWw6QXR0cmli
        dXRlU3RhdGVtZW50Pjwvc2FtbDpBc3NlcnRpb24+PC9zYW1scDpSZXNwb25zZT4=
    SAML
    expect(response).to redirect_to(dashboard_url(:login_success => 1))
    expect(session[:saml_unique_id]).to eq unique_id
  end

  it "should decode an actual saml response using certificate text" do
    unique_id = 'max.leon@presidio.edu'

    account_with_saml

    @aac = @account.authentication_providers.first
    @aac.idp_entity_id = 'http://phpsite/simplesaml/saml2/idp/metadata.php'
    @aac.login_attribute = 'nameid'
    @aac.certificate_text = <<-CERT
-----BEGIN CERTIFICATE-----
MIIERTCCAy2gAwIBAgIJAKjYyCU9/ZbsMA0GCSqGSIb3DQEBBQUAMHQxCzAJBgNV
BAYTAlVTMQswCQYDVQQIEwJJRDEPMA0GA1UEBxMGTW9zY293MRMwEQYDVQQKEwpQ
b3B1bGkgSW5jMRIwEAYDVQQDEwlwb3B1bGkuY28xHjAcBgkqhkiG9w0BCQEWD2ph
bWVzQHBvcHVsaS5jbzAeFw0xNDAxMTUxODI4MDFaFw0yNDAxMTUxODI4MDFaMHQx
CzAJBgNVBAYTAlVTMQswCQYDVQQIEwJJRDEPMA0GA1UEBxMGTW9zY293MRMwEQYD
VQQKEwpQb3B1bGkgSW5jMRIwEAYDVQQDEwlwb3B1bGkuY28xHjAcBgkqhkiG9w0B
CQEWD2phbWVzQHBvcHVsaS5jbzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
ggEBAN5ubDPuF6p5/81CKExS7NayhMO9xsVWfFR8zGAKVayDhgP7DwQUM+fs8MxI
JFXa2Zu3YYiWbwuVYaa1DVNOMJ4Jr/wy2DtxYO5q83LmZDC26LgaqthBh96ETTy4
Bo1vBnXufjJZ7bmYidHb87fu89+c8SrCJHShaPUkWi2qrjcx1ybhpKy1GUwLtE8/
t5SItc//KklGsGi6qe0LswRM8pfSw+6moR4tZxGzcn7cxCy/pBFv8Xsq/4wtCA7h
2+ED336EpfOtxG7tOcC2GfKkykjk3JzPe9IfC+2O3oj25dv07lU9kQSfLc6GYYgY
QExHN3a2RJ6uQYHuoicVR3u8iwcCAwEAAaOB2TCB1jAdBgNVHQ4EFgQUihk0243g
SiflxW5AJV3O7HxMSvUwgaYGA1UdIwSBnjCBm4AUihk0243gSiflxW5AJV3O7HxM
SvWheKR2MHQxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJJRDEPMA0GA1UEBxMGTW9z
Y293MRMwEQYDVQQKEwpQb3B1bGkgSW5jMRIwEAYDVQQDEwlwb3B1bGkuY28xHjAc
BgkqhkiG9w0BCQEWD2phbWVzQHBvcHVsaS5jb4IJAKjYyCU9/ZbsMAwGA1UdEwQF
MAMBAf8wDQYJKoZIhvcNAQEFBQADggEBADRdwvghXbBa7L7waRf0MO5CVnbaNgsR
treSxCwk9JxtJQGRJ55ABEawtX+vpCUhNee6QgInMSY6MCszMTspJ1N+388Iho1e
BRxEnyJQ7VfzwX43+wJ4lzTUyt2JXFg1URLHKQyk78Fo8fQcu2yaO9umVx8QrsrF
5qmVJGeCB03yFZ2+RhcPU1YuA5ZZUeGjTP/w49hu/c6BGVlM3Dq2S4iCWs6HzpjA
uCK+V++7KsIsN9Z5LkNwRO3Rzvits3Hr37MS3GMDJNB5P9w4hDltn777dIszc3Pu
QEieVkZXWRftqXTXS/9iXAjAKPTF20Uu6/t1jXdHkTMxCThZ/L78dkI=
-----END CERTIFICATE-----
    CERT
    @aac.save

    user_with_pseudonym(:active_all => true, :username => unique_id)
    @pseudonym.account = @account
    @pseudonym.save!

    controller.request.env['canvas.domain_root_account'] = @account
    post :create, :SAMLResponse => <<-SAML
        PHNhbWxwOlJlc3BvbnNlIHhtbG5zOnNhbWxwPSJ1cm46b2FzaXM6bmFtZXM6dGM6U0FNTDoyLjA6cHJv
        dG9jb2wiIHhtbG5zOnNhbWw9InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDphc3NlcnRpb24iIElE
        PSJfMzY2MDExZGEzZjNlYTkyOWYwNWFmZmExNmY4YjVjNjU5ZjRkZTU2NDNlIiBWZXJzaW9uPSIyLjAi
        IElzc3VlSW5zdGFudD0iMjAxNi0wNS0yNFQyMTo0MTo0MFoiIERlc3RpbmF0aW9uPSJodHRwczovL3By
        ZXNpZGlvLmhvdGNoYWxrZW1iZXIuY29tL3NhbWxfY29uc3VtZSIgSW5SZXNwb25zZVRvPSJjZjM1N2Zj
        MGRkNjhjNjI5MzkxZGU2M2Y1NmY1NTk5YTMwYjQ4YTc5ZGMiPjxzYW1sOklzc3Vlcj5wb3B1bGkuY288
        L3NhbWw6SXNzdWVyPjxkczpTaWduYXR1cmUgeG1sbnM6ZHM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAv
        MDkveG1sZHNpZyMiPgogIDxkczpTaWduZWRJbmZvPjxkczpDYW5vbmljYWxpemF0aW9uTWV0aG9kIEFs
        Z29yaXRobT0iaHR0cDovL3d3dy53My5vcmcvMjAwMS8xMC94bWwtZXhjLWMxNG4jIi8+CiAgICA8ZHM6
        U2lnbmF0dXJlTWV0aG9kIEFsZ29yaXRobT0iaHR0cDovL3d3dy53My5vcmcvMjAwMC8wOS94bWxkc2ln
        I3JzYS1zaGExIi8+CiAgPGRzOlJlZmVyZW5jZSBVUkk9IiNfMzY2MDExZGEzZjNlYTkyOWYwNWFmZmEx
        NmY4YjVjNjU5ZjRkZTU2NDNlIj48ZHM6VHJhbnNmb3Jtcz48ZHM6VHJhbnNmb3JtIEFsZ29yaXRobT0i
        aHR0cDovL3d3dy53My5vcmcvMjAwMC8wOS94bWxkc2lnI2VudmVsb3BlZC1zaWduYXR1cmUiLz48ZHM6
        VHJhbnNmb3JtIEFsZ29yaXRobT0iaHR0cDovL3d3dy53My5vcmcvMjAwMS8xMC94bWwtZXhjLWMxNG4j
        Ii8+PC9kczpUcmFuc2Zvcm1zPjxkczpEaWdlc3RNZXRob2QgQWxnb3JpdGhtPSJodHRwOi8vd3d3Lncz
        Lm9yZy8yMDAwLzA5L3htbGRzaWcjc2hhMSIvPjxkczpEaWdlc3RWYWx1ZT5XVGMwMXNMZVJwQWR2T2VW
        QzdSWUJ5SEU3ODQ9PC9kczpEaWdlc3RWYWx1ZT48L2RzOlJlZmVyZW5jZT48L2RzOlNpZ25lZEluZm8+
        PGRzOlNpZ25hdHVyZVZhbHVlPjBSeVNkM0NUMFpVWmZtNW5kR2FJYSsyakRCS1pPT1FPQTI5Y1Jkc0NG
        ZVkybGVOc2k1bEsvbGxuT0ZuVk1aZFFuanBORk01aTJlbEowMlpRUWNWYUdqdjVqVVVTYVlSUitqcGdv
        ei92ZTNjQUdyRmNLUUZkVjNSVGxraU5jOWdvdjhJbll2L080L2dHRSsrTmtvVUhmL0NOcjJZdDdIcWla
        YVBlQzE5WEIxYkszRjBENGR3Q0ZPc0xQRXBRUGZHK2s3ZkRHbGd2ZE9kLytZUHNXTm55amh2UUpqOCtK
        dmJJVENMMlY1WmJHaVB6ODNaK3JnNVFjZFMreFh5dVhmZEFhQzdFZGVrMG54RUd6eWt0R214RU1GVHJi
        cHlpdmJYS0JyTTZYR2I4NVlvbnRqQThWMW15d0ZoRW5zU2M4b2hpcG9RdjkyeEs1aVczVmk5MW8vNTJj
        QT09PC9kczpTaWduYXR1cmVWYWx1ZT4KPC9kczpTaWduYXR1cmU+PHNhbWxwOlN0YXR1cz48c2FtbHA6
        U3RhdHVzQ29kZSBWYWx1ZT0idXJuOm9hc2lzOm5hbWVzOnRjOlNBTUw6Mi4wOnN0YXR1czpTdWNjZXNz
        Ii8+PC9zYW1scDpTdGF0dXM+PHNhbWw6QXNzZXJ0aW9uIHhtbG5zOnhzaT0iaHR0cDovL3d3dy53My5v
        cmcvMjAwMS9YTUxTY2hlbWEtaW5zdGFuY2UiIHhtbG5zOnhzPSJodHRwOi8vd3d3LnczLm9yZy8yMDAx
        L1hNTFNjaGVtYSIgSUQ9Il9kNjViYWEyOTRkM2MxZDdkMzg4YTExZWYyYWFhYzY2NDg2MTM0NjVhM2Ii
        IFZlcnNpb249IjIuMCIgSXNzdWVJbnN0YW50PSIyMDE2LTA1LTI0VDIxOjQxOjQwWiI+PHNhbWw6SXNz
        dWVyPnBvcHVsaS5jbzwvc2FtbDpJc3N1ZXI+PHNhbWw6U3ViamVjdD48c2FtbDpOYW1lSUQgRm9ybWF0
        PSJ1cm46b2FzaXM6bmFtZXM6dGM6U0FNTDoxLjE6bmFtZWlkLWZvcm1hdDplbWFpbEFkZHJlc3MiPm1h
        eC5sZW9uQHByZXNpZGlvLmVkdTwvc2FtbDpOYW1lSUQ+PHNhbWw6U3ViamVjdENvbmZpcm1hdGlvbiBN
        ZXRob2Q9InVybjpvYXNpczpuYW1lczp0YzpTQU1MOjIuMDpjbTpiZWFyZXIiPjxzYW1sOlN1YmplY3RD
        b25maXJtYXRpb25EYXRhIE5vdE9uT3JBZnRlcj0iMjAxNi0wNS0yNFQyMTo0Njo0MFoiIFJlY2lwaWVu
        dD0iaHR0cHM6Ly9wcmVzaWRpby5ob3RjaGFsa2VtYmVyLmNvbS9zYW1sX2NvbnN1bWUiIEluUmVzcG9u
        c2VUbz0iY2YzNTdmYzBkZDY4YzYyOTM5MWRlNjNmNTZmNTU5OWEzMGI0OGE3OWRjIi8+PC9zYW1sOlN1
        YmplY3RDb25maXJtYXRpb24+PC9zYW1sOlN1YmplY3Q+PHNhbWw6Q29uZGl0aW9ucyBOb3RCZWZvcmU9
        IjIwMTYtMDUtMjRUMjE6NDE6MTBaIiBOb3RPbk9yQWZ0ZXI9IjIwMTYtMDUtMjRUMjE6NDY6NDBaIj48
        c2FtbDpBdWRpZW5jZVJlc3RyaWN0aW9uPjxzYW1sOkF1ZGllbmNlPmh0dHA6Ly9wcmVzaWRpby5ob3Rj
        aGFsa2VtYmVyLmNvbS9zYW1sMjwvc2FtbDpBdWRpZW5jZT48L3NhbWw6QXVkaWVuY2VSZXN0cmljdGlv
        bj48L3NhbWw6Q29uZGl0aW9ucz48c2FtbDpBdXRoblN0YXRlbWVudCBBdXRobkluc3RhbnQ9IjIwMTYt
        MDUtMjRUMjE6NDE6NDBaIiBTZXNzaW9uSW5kZXg9Il8wODhiZjE2NDA2MTNmNDg2YmVhYjUwOTBmMjJi
        NDBmYjU2NTMxYWVlMzAiPjxzYW1sOkF1dGhuQ29udGV4dD48c2FtbDpBdXRobkNvbnRleHRDbGFzc1Jl
        Zj51cm46b2FzaXM6bmFtZXM6dGM6U0FNTDoyLjA6YWM6Y2xhc3NlczpQYXNzd29yZDwvc2FtbDpBdXRo
        bkNvbnRleHRDbGFzc1JlZj48L3NhbWw6QXV0aG5Db250ZXh0Pjwvc2FtbDpBdXRoblN0YXRlbWVudD48
        c2FtbDpBdHRyaWJ1dGVTdGF0ZW1lbnQ+PHNhbWw6QXR0cmlidXRlIE5hbWU9IkZpcnN0TmFtZSI+PHNh
        bWw6QXR0cmlidXRlVmFsdWUgeHNpOnR5cGU9InhzOnN0cmluZyI+SG90PC9zYW1sOkF0dHJpYnV0ZVZh
        bHVlPjwvc2FtbDpBdHRyaWJ1dGU+PHNhbWw6QXR0cmlidXRlIE5hbWU9Ikxhc3ROYW1lIj48c2FtbDpB
        dHRyaWJ1dGVWYWx1ZSB4c2k6dHlwZT0ieHM6c3RyaW5nIj5UZXN0PC9zYW1sOkF0dHJpYnV0ZVZhbHVl
        Pjwvc2FtbDpBdHRyaWJ1dGU+PHNhbWw6QXR0cmlidXRlIE5hbWU9IkVtYWlsIj48c2FtbDpBdHRyaWJ1
        dGVWYWx1ZSB4c2k6dHlwZT0ieHM6c3RyaW5nIj5tYXhsZW9ucHJlc2lkaW9lZHU8L3NhbWw6QXR0cmli
        dXRlVmFsdWU+PC9zYW1sOkF0dHJpYnV0ZT48L3NhbWw6QXR0cmlidXRlU3RhdGVtZW50Pjwvc2FtbDpB
        c3NlcnRpb24+PC9zYW1scDpSZXNwb25zZT4=
    SAML
    expect(response).to redirect_to(dashboard_url(:login_success => 1))
    expect(session[:saml_unique_id]).to eq unique_id
  end
end
