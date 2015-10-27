#
# Copyright (C) 2011 - 2014 Instructure, Inc.
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

class Login::CanvasController < ApplicationController
  include Login::Shared

  before_filter :forbid_on_files_domain
  before_filter :run_login_hooks, only: [:new, :create]

  protect_from_forgery except: :create

  def new
    @pseudonym_session = PseudonymSession.new
    @headers = false
    @is_prelogin = true unless params[:direct]
    @aacs_with_buttons = @domain_root_account.authentication_providers.active.select(&:login_button?)
    flash.now[:error] = params[:message] if params[:message]

    maybe_render_mobile_login
  end

  def create
    # reset the session id cookie to prevent session fixation.
    reset_session_for_login
    load_root_account(params[:account_id])

    # Check referer and authenticity token.  If the token is invalid but the referer is trusted
    # and one is not provided then continue.  If the referer is trusted and they provide a token
    # we still want to check it.
    if params.key?(request_forgery_protection_token) || !@domain_root_account.trusted_referer?(request.referer)
      begin
        verify_authenticity_token
      rescue ActionController::InvalidAuthenticityToken
        return unsuccessful_login(t("Invalid Authenticity Token"))
      end
    end

    if params[:pseudonym_session].blank? || params[:pseudonym_session][:password].blank?
      return unsuccessful_login(t("No password was given"))
    end

    # strip leading and trailing whitespace off the entered unique id. some
    # mobile clients (e.g. android) will add a space after the login when using
    # autocomplete. this would prevent us from recognizing someone's username,
    # making them unable to login.
    params[:pseudonym_session][:unique_id].try(:strip!)

    # Try to use authlogic's built-in login approach first
    @pseudonym_session = @domain_root_account.pseudonym_sessions.new(params[:pseudonym_session])
    @pseudonym_session.remote_ip = request.remote_ip
    found = @pseudonym_session.save

    # look for LDAP pseudonyms where we get the unique_id back from LDAP
    if !found && !@pseudonym_session.attempted_record
      found = @domain_root_account.authentication_providers.active.where(auth_type: 'ldap').any? do |aac|
        next unless aac.identifier_format.present?
        res = aac.ldap_bind_result(params[:pseudonym_session][:unique_id], params[:pseudonym_session][:password])
        unique_id = res.first[aac.identifier_format].first if res
        next unless unique_id && (pseudonym = @domain_root_account.pseudonyms.active.by_unique_id(unique_id).first)

        pseudonym.instance_variable_set(:@ldap_result, res.first)
        @pseudonym_session = PseudonymSession.new(pseudonym, params[:pseudonym_session][:remember_me] == "1")
        @pseudonym_session.save
      end
    end

    if !found && params[:pseudonym_session]
      search_account_ids = Account.all(:select => :id).collect(&:id)
      pseudonym = Pseudonym.authenticate(params[:pseudonym_session],
                                         search_account_ids,
                                         request.remote_ip)
      if pseudonym && pseudonym != :too_many_attempts
        @pseudonym_session = PseudonymSession.new(pseudonym, params[:pseudonym_session][:remember_me] == "1")
        found = @pseudonym_session.save
      end
    end

    if pseudonym == :too_many_attempts || @pseudonym_session.too_many_attempts?
      unsuccessful_login t("Too many failed login attempts. Please try again later or contact your system administrator.")
      return
    end

    pseudonym = @pseudonym_session && @pseudonym_session.record
    # If the user's @domain_root_account has been deleted, feel free to share that information
    if pseudonym && (!pseudonym.user || pseudonym.user.unavailable?)
      unsuccessful_login t("That user account has been deleted.  Please contact your system administrator to have your account re-activated.")
      return
    end

    # If the user is registered and logged in, redirect them to their dashboard page
    if found
      # Call for some cleanups that should be run when a user logs in
      user = pseudonym.login_assertions_for_user
      successful_login(user, pseudonym)
    else
      unsuccessful_login t("Incorrect username and/or password")
    end
  end

  def resolve
    if params[:prelogin].blank? || params[:prelogin][:unique_id].blank?
      render :json => {:errors => {:unique_id => t('errors.invalid_unique_id', "No email was given")}}, :status => :bad_request
      return
    end

    # strip leading and trailing whitespace off the entered unique id. some
    # mobile clients (e.g. android) will add a space after the login when using
    # autocomplete. this would prevent us from recognizing someone's username,
    # making them unable to login.
    params[:prelogin][:unique_id].try(:strip!)

    # find the user associated to the supplied email address
    possible_users = []
    Account.root_accounts.each do |root_account|
      user_list = UserList.new(params[:prelogin][:unique_id], :root_account => root_account, :search_method => :closed).users
      possible_users.concat(user_list)
      break unless user_list.empty?
    end
    user = (possible_users ? (possible_users.uniq.first) : nil)

    # find the pseudonym associated to the user, giving preference to a matching unique id. If a matching unique id is not found,
    # fall back to the first active pseudonym for the user
    if user
      pseudonym = user.pseudonyms.active.select { |p| p.unique_id == params[:prelogin][:unique_id] }.first
      pseudonym = user.pseudonyms.active.first unless pseudonym
    end
    unless user && pseudonym
      render :json => {:errors => {:unique_id => t('errors.no_matching_user', "HotChalk Ember doesn't have an account for user: %{user}", :user => params[:prelogin][:unique_id])}}, :status => :not_found
      return
    end

    # check authentication type for the pseudonym's root account
    root_account = Account.find(pseudonym.root_account_id)
    aac = root_account.authentication_providers.active.first
    response = {:account_id => pseudonym.root_account_id}
    if aac.nil?
      response[:auth_type] = 'canvas'
    else
      response[:auth_type] = aac.auth_type
      response[:account_name] = root_account.name
      if aac.auth_type == 'cas'
        response.merge!({:auth_url => "/login?account_id=#{root_account.id}"})
      elsif aac.auth_type == 'hmac'
        response.merge!({:auth_url => aac.log_in_url})
      elsif aac.auth_type == 'saml'
        response.merge!({:auth_url => "/login?account_id=#{root_account.id}"})
      elsif aac.auth_type == 'ldap'
        response[:auth_type] = 'canvas'
      end
    end
    render :json => response
  end

  protected

  def unsuccessful_login(message)
    if request.format.json?
      return render :json => {:errors => [message]}, :status => :bad_request
    end
    flash[:error] = message
    @errored = true
    @headers = false
    maybe_render_mobile_login :bad_request
  end

  def maybe_render_mobile_login(status = nil)
    if mobile_device?
      @login_handle_name = @domain_root_account.login_handle_name_with_inference
      @login_handle_is_email = @login_handle_name == AccountAuthorizationConfig.default_login_handle_name
      js_env(
        GOOGLE_ANALYTICS_KEY: Setting.get('google_analytics_key', nil),
      )
      render :mobile_login, layout: 'mobile_auth', status: status
    else
      render :new, status: status
    end
  end
end
