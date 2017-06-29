require 'nokogiri'
require 'diffy'

class DomainValidator

  TAG = "domain_validation"
  SEARCH_FIELDS = {
    AccountAuthorizationConfig => [:entity_id, :idp_entity_id],
    AccountNotification => [:message],
    AssessmentQuestion => [:question_data],
    Assignment => [:description],
    CalendarEvent => [:description],
    ContentTag => [:url],
    ConversationMessage => [:body],
    Course => [:syllabus_body],
    # DelayedMessage => [:link, :summary],
    DiscussionEntry => [:message],
    DiscussionTopic::MaterializedView => [:json_structure],
    DiscussionTopic => [:message],
    EportfolioEntry => [:content],
    Group => [:description],
    # Message => [:body, :url, :html_body],
    OauthRequest => [:return_url, :original_host_with_port],
    PageComment => [:message],
    PluginSetting => [:settings],
    Quizzes::QuizQuestion => [:question_data],
    Quizzes::QuizSubmissionEvent => [:event_data],
    Quizzes::QuizSubmissionSnapshot => [:data],
    Quizzes::QuizSubmission => [:submission_data, :quiz_data],
    Quizzes::Quiz => [:description, :quiz_data],
    RubricAssessment => [:data],
    StreamItem => [:data],
    SubmissionComment => [:comment],
    Submission => [:body, :url],
    UserProfileLink => [:url],
    UserProfile => [:bio],
    User => [:avatar_image_url],
    Version => [:yaml],
    WikiPage => [:body, :url]
  }

  attr_accessor :domain_regex, :issues, :visited_urls

  def initialize(search_domain, replace_domain, replace_protocol, debug)
    domain_regex = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(\/.*)?$/
    raise "Invalid domain name!" unless domain_regex.match(search_domain) && (replace_domain.blank? || domain_regex.match(replace_domain))
    @search_domain = search_domain
    @replace_domain = replace_domain
    @replace_protocol = replace_protocol
    @debug = debug
    @domain_regex = %r{\w+:?(\/\/|%2F%2F)#{Regexp.quote(@search_domain)}}
    @issues = []
    @visited_urls = {}
  end

  # Checks all relevant data points for references to the domain name supplied as an argument to this validator.
  def check_all
    begin
      SEARCH_FIELDS.each_key {|model_class| check_class(model_class, SEARCH_FIELDS[model_class])}
    rescue Exception => e
      Rails.logger.error "[DOMAIN-VALIDATOR] Domain validation failed: #{e.inspect}"
    end
  end

  def check_class(model_class, attributes)
    Rails.logger.info "[DOMAIN-VALIDATOR] Checking model class #{model_class.name}..."
    real_time = Benchmark.realtime do
      conditions = attributes.map {|attr| "#{attr.to_s} LIKE '%#{@search_domain}%'"}.join(' OR ')
      ids = model_class.where(conditions).pluck(model_class.primary_key)
      ids.each {|id| check_model(model_class, id, attributes)}
    end
    Rails.logger.info "[DOMAIN-VALIDATOR] Finished checking model class #{model_class.name} in #{real_time.to_i}s"
  end

  def check_model(model_class, id, attributes)
    attributes.each do |attr|
      old_value = ActiveRecord::Base.connection.select_value("SELECT #{attr.to_s} FROM #{model_class.quoted_table_name} WHERE #{model_class.primary_key.to_s} = #{id}")
      next unless old_value.present?
      if @replace_domain.present?
        if @replace_protocol.present?
          new_value = old_value.gsub(/(http|https)\:\/\/#{Regexp.quote(@search_domain)}/, (@replace_protocol + '://' + @replace_domain))
        else
          new_value = old_value.gsub(/(?<prefix>(\/\/|%2F%2F))#{Regexp.quote(@search_domain)}/, ('\k<prefix>' + @replace_domain))
        end
        next unless new_value != old_value
        Rails.logger.info "[DOMAIN-VALIDATOR] Replacing #{model_class.name}(#{id}).#{attr.to_s}:\n#{Diffy::Diff.new(old_value + "\n", new_value + "\n", :diff => '-U 0')}" if @debug
        begin
          model_class.transaction do
            model_class.where(model_class.primary_key => id).update_all("#{attr} = #{ActiveRecord::Base.connection.quote(new_value)}")
          end
        rescue Exception => e
          Rails.logger.error "[DOMAIN-VALIDATOR] Domain replacement failed: #{e.inspect}"
        end
      elsif old_value.match(@domain_regex)
        Rails.logger.info "[DOMAIN-VALIDATOR] Detected #{model_class.name}(#{id}).#{attr.to_s}: #{ActionView::Base.new.excerpt(old_value, @search_domain, :radius => 10)}" if @debug
      end
    end
  end
end
