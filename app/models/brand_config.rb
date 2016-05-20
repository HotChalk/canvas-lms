class BrandConfig < ActiveRecord::Base
  include BrandableCSS

  self.primary_key = 'md5'
  serialize :variables, Hash

  OVERRIDE_TYPES = [:js_overrides, :css_overrides, :mobile_js_overrides, :mobile_css_overrides].freeze
  ATTRS_TO_INCLUDE_IN_MD5 = ([:variables, :parent_md5] + OVERRIDE_TYPES).freeze

  attr_accessible(*([:variables] + OVERRIDE_TYPES))

  validates :variables, presence: true, unless: :overrides?
  validates :md5, length: {is: 32}

  before_validation :generate_md5
  before_update do
    raise 'BrandConfigs are a key-value mapping of config variables and an md5 digest '\
          'of those variables, so they are immutable. You do not update them, you just '\
          'save a new one and it will generate the new md5 for you'
  end

  belongs_to :parent, class_name: 'BrandConfig', foreign_key: 'parent_md5'
  has_many :accounts, foreign_key: 'brand_config_md5'

  scope :without_k12, lambda { where("md5 != ?", BrandConfig.k12_config) }

  scope :shared, -> (account = nil) {
    shared_scope = where(share: true)
    shared_scope = shared_scope.without_k12 unless account && account.feature_enabled?(:k12)
    shared_scope
  }

  def self.for(attrs)
    attrs = attrs.with_indifferent_access.slice(*ATTRS_TO_INCLUDE_IN_MD5)
    return default if attrs.values.all?(&:blank?)

    new_config = new(attrs)
    new_config.parent_md5 = attrs[:parent_md5]
    existing_config = where(md5: new_config.generate_md5).first
    existing_config || new_config
  end

  def self.default
    new
  end

  def self.k12_config
    BrandConfig.where(name: 'K12 Theme', share: true).first
  end

  def default?
    ([:variables] + OVERRIDE_TYPES).all? {|a| self[a].blank? }
  end

  def generate_md5
    self.id = BrandConfig.md5_for(self)
  end

  def self.md5_for(brand_config)
    Digest::MD5.hexdigest(ATTRS_TO_INCLUDE_IN_MD5.map { |a| brand_config[a] }.join)
  end

  def get_value(variable_name)
    effective_variables[variable_name]
  end

  def overrides?
    OVERRIDE_TYPES.any? { |o| self[o].present? }
  end

  def effective_variables
    @effective_variables ||=
      chain_of_ancestor_configs.map(&:variables).reduce(variables, &:reverse_merge) || {}
  end

  def chain_of_ancestor_configs
    @ancestor_configs ||= [self] + (parent && parent.chain_of_ancestor_configs).to_a
  end

  def save_unless_dup!
    unless BrandConfig.where(md5: self.md5).exists?
      self.save!
    end
  end

  def to_scss
    "// This file is autogenerated by brand_config.rb as a result of running `rake brand_configs:write`\n" +
    effective_variables.map do |name, value|
      next unless (config = BrandableCSS.variables_map[name])
      value = %{url("#{value}")} if config['type'] == 'image'
      "$#{name}: #{value};"
    end.compact.join("\n")
  end

  def scss_file
    scss_dir.join('_brand_variables.scss')
  end

  def to_json
    BrandableCSS.all_brand_variable_values(self).to_json
  end

  def json_file
    public_brand_dir.join("variables-#{BrandableCSS.default_variables_md5}.json")
  end

  def scss_dir
    BrandableCSS.branded_scss_folder.join(md5)
  end

  def public_brand_dir
    BrandableCSS.public_brandable_css_folder.join(md5)
  end

  def public_folder
    "dist/brandable_css/#{md5}"
  end

  def public_json_path
    "#{public_folder}/variables-#{BrandableCSS.default_variables_md5}.json"
  end

  def save_scss_file!
    logger.info "saving brand variables file: #{scss_file}"
    scss_dir.mkpath
    scss_file.write(to_scss)
  end

  def save_json_file!
    logger.info "saving brand variables file: #{json_file}"
    public_brand_dir.mkpath
    json_file.write(to_json)
    move_json_to_s3_if_enabled!
  end

  def move_json_to_s3_if_enabled!
    return unless Canvas::Cdn.enabled?
    s3_uploader.upload_file(public_json_path)
    File.delete(json_file)
  end

  def s3_uploader
    @s3_uploaderer ||= Canvas::Cdn::S3Uploader.new
  end

  def save_all_files!
    save_scss_file!
    save_json_file!
  end

  def remove_scss_dir!
    return unless scss_dir.exist?
    logger.info "removing: #{scss_dir}"
    scss_dir.rmtree
  end

  def compile_css!(opts=nil)
    BrandableCSS.compile_brand!(md5, opts)
  end

  def css_and_js_overrides
    Rails.cache.fetch([self, 'css_and_js_overrides']) do
      chain_of_ancestor_configs.each_with_object({}) do |brand_config, includes|
        BrandConfig::OVERRIDE_TYPES.each do |override_type|
          if brand_config[override_type].present?
            (includes[override_type] ||= []).unshift(brand_config[override_type])
          end
        end
      end
    end
  end

  def sync_to_s3_and_save_to_account!(progress, account_id)
    save_and_sync_to_s3!(progress)
    act = Account.find(account_id)
    old_md5 = act.brand_config_md5
    act.brand_config_md5 = md5
    act.save!
    BrandConfig.destroy_if_unused(old_md5)
  end

  def save_and_sync_to_s3!(progress=nil)
    progress.update_completion!(5) if progress
    save_all_files!
    progress.update_completion!(10) if progress
    compile_css! on_progress: -> (percent_complete) {
      # send at most 1 UPDATE query per 2 seconds
      if progress && (progress.updated_at < 1.seconds.ago)
        total_percent = 10 + percent_complete * 0.9
        progress.update_completion!(total_percent)
      end
    }
    Canvas::Cdn.push_to_s3!
  end

  def self.destroy_if_unused(md5)
    return unless md5
    unused_brand_config = BrandConfig.
      where(md5: md5).
      where("NOT EXISTS (?)", Account.where("brand_config_md5=brand_configs.md5")).
      where("NOT share").
      first
    if unused_brand_config
      unused_brand_config.destroy
      unused_brand_config.remove_scss_dir!
    end
  end

  def self.clean_unused_from_db!
    BrandConfig.
      where("NOT EXISTS (?)", Account.where("brand_config_md5=brand_configs.md5")).
      where('NOT share').
      # When someone is actively working in the theme editor, it just saves one
      # in their session, so only delete stuff that is more than a week old,
      # to not clear out a theme someone was working on.
      where(["created_at < ?", 1.week.ago]).
      delete_all
  end

end
