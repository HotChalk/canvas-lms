class AccountAuthorizationConfig::HMAC < AccountAuthorizationConfig::Delegated

  def self.sti_name
    'hmac'
  end

  def self.recognized_params
    [ :auth_type, :hmac_shared_secret, :hmac_timestamp_range, :log_in_url, :position ]
  end

  validates_presence_of :hmac_shared_secret
  validates_presence_of :hmac_timestamp_range
  validates_presence_of :log_in_url

end