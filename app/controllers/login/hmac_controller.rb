class Login::HmacController < Login::CanvasController
  include Login::Shared

  protect_from_forgery except: :create

  before_filter :forbid_on_files_domain
  # before_filter :run_login_hooks, :check_sa_delegated_cookie, only: :new

  def create
    load_root_account(params[:account_id])
    unless aac
      return unsuccessful_login("HMAC authentication not configured for account #{@domain_root_account.name}")
    end
    unless [:auth, :userId, :timestamp].all? { |p| params.key? p }
      return unsuccessful_login("Invalid HMAC parameters")
    end
    @hmac_shared_secret = aac.hmac_shared_secret
    @hmac_timestamp_range = aac.hmac_timestamp_range
    if validate_mac?
      @pseudonym = @domain_root_account.pseudonyms.custom_find_by_unique_id(params[:userId])
      if @pseudonym
        # Reset the session
        reset_session_for_login
        # Successful login and we have a user
        @domain_root_account.pseudonym_sessions.create!(@pseudonym, false)
        @user = @pseudonym.login_assertions_for_user
        successful_login(@user, @pseudonym)
      else
        logger.warn "Received HMAC login request for unknown user: #{params[:userId]}"
        unsuccessful_login("Account not found. Please contact your System Administrator.")
      end
    else
      unsuccessful_login("Unable to log in. Please contact your System Administrator.")
    end
  end

  def validate_mac?
    valid_timestamp? && hash_match?
  end

  def valid_timestamp?
    received_ts = params[:timestamp].to_i / 1000
    actual_ts = Time.now.to_i
    valid = (received_ts - actual_ts).abs <= @hmac_timestamp_range
    logger.warn "Denying access for user ID [#{params[:userId]}]: expired timestamp; received [#{received_ts}] actual [#{actual_ts}]" unless valid
    valid
  end

  def hash_match?
    calculated_hash = calculate_hash
    match = (calculated_hash.casecmp(params[:auth]) == 0)
    logger.debug "Supplied hash [#{params[:auth]}]; calculated hash [#{calculated_hash}]"
    logger.warn "Denying access for user ID [#{params[:userId]}]: wrong hash" unless match
    match
  end

  def calculate_hash
    param_string = '' + params[:timestamp] + params[:userId] + @hmac_shared_secret
    param_string = param_string.encode('UTF-8')
    logger.debug "HMAC parameter string: #{param_string}"
    Digest::MD5.hexdigest(param_string)
  end

  protected

  def aac
    @aac ||= begin
      scope = @domain_root_account.account_authorization_configs.where(auth_type: 'hmac')
      params[:id] ? scope.find(params[:id]) : scope.first!
    end
  end
end