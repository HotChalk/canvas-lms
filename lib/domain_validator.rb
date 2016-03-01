require 'nokogiri'

class DomainValidator

  TAG = "domain_validation"

  # retrieves the validation job
  def self.current_progress
    Progress.where(:tag => TAG, :context_type => 'Account', :context_id => Account.site_admin.id).last
  end

  # creates a new validation job
  def self.queue(domain)
    progress = current_progress
    return progress if progress && progress.pending?

    progress ||= Progress.new(:tag => TAG, :context => Account.site_admin)
    progress.reset!
    progress.process_job(self, :process, {}, domain)
    progress
  end

  def self.process(progress, domain)
    validator = self.new(domain)
    validator.check_all(progress)
    progress.set_results({:issues => validator.issues, :completed_at => Time.now.utc})
  rescue
    report_id = Canvas::Errors.capture_exception(:domain_validation, $ERROR_INFO)[:error_report]
    progress.workflow_state = 'failed'
    progress.set_results({error_report_id: report_id, completed_at: Time.now.utc})
  end

  attr_accessor :domain_regex, :issues, :visited_urls

  def initialize(domain)
    self.domain_regex = %r{\w+:?\/\/#{domain}} if domain
    self.issues = []
    self.visited_urls = {}
  end

  # Checks all relevant data points for references to the domain name supplied as an argument to this validator.
  # Current data points included are:
  #
  # account_notifications.message
  # assessment_questions.question_data
  # assignments.description
  # calendar_events.description
  # conversation_messages.body
  # courses.syllabus_body
  # delayed_messages.link
  # delayed_messages.summary
  # discussion_entries.message
  # discussion_topics.message
  # groups.description
  # messages.body
  # messages.html_body
  # messages.url
  # quiz_questions.question_data
  # quizzes.description
  # quizzes.quiz_data
  # wiki_pages.body


  #!!!!!!!!!!!!!!!!!!!!!
  # quizzes                           | quiz_data
  # quiz_submissions                  | quiz_data
  # quiz_submissions                  | submission_data
  # stream_items                      | data
  # submission_comments               | comment
  # submissions                       | body
  # users                             | avatar_image_url
  # versions                          | yaml
  def check_all(progress)
    active_account_ids = Account.active.pluck(:id)

    # Account notifications
    scope = AccountNotification.where(account_id: active_account_ids).where("NOW() BETWEEN start_at AND end_at")
    issues = check_scope(scope, :message)
    self.issues += issues
    progress.update_completion! 5

    # Assessment questions
    scope = AssessmentQuestion.active
    issues = check_scope(scope)
    self.issues += issues
    progress.update_completion! 10

    # Assignments
    scope = Assignment.active
    issues = check_scope(scope, :description)
    self.issues += issues
    progress.update_completion! 15

    # Calendar events
    scope = CalendarEvent.active
    issues = check_scope(scope, :description)
    self.issues += issues
    progress.update_completion! 20

    # Conversation messages
    scope = ConversationMessage.all
    issues = check_scope(scope, :body)
    self.issues += issues
    progress.update_completion! 25

    # Courses
    scope = Course.active.where(account_id: active_account_ids).where("conclude_at IS NULL OR conclude_at > NOW()")
    issues = check_scope(scope, :syllabus_body)
    self.issues += issues
    progress.update_completion! 30

    # Delayed messages
    scope = DelayedMessage.in_state(:pending).where(root_account_id: active_account_ids)
    issues = check_scope(scope, :link, :summary)
    self.issues += issues
    progress.update_completion! 35

    # Discussion entries
    scope = DiscussionEntry.active
    issues = check_scope(scope, :message)
    self.issues += issues
    progress.update_completion! 40

    # Discussion topics
    scope = DiscussionTopic.active
    issues = check_scope(scope, :message)
    self.issues += issues
    progress.update_completion! 45

    # Groups
    scope = Group.active.where(root_account_id: active_account_ids)
    issues = check_scope(scope, :description)
    self.issues += issues
    progress.update_completion! 50

    # Messages
    # scope = Message.where(root_account_id: active_account_ids)
    # issues = check_scope(scope, :body, :html_body, :url)
    # self.issues += issues
    # progress.update_completion! 50

    # Quiz questions
    scope = Quizzes::QuizQuestion.active
    issues = check_scope(scope)
    self.issues += issues
    progress.update_completion! 55

    # Quizzes
    scope = Quizzes::Quiz.active
    issues = check_scope(scope, :description)
    self.issues += issues
    progress.update_completion! 60

    # Wiki pages
    scope = WikiPage.not_deleted
    issues = check_scope(scope, :body)
    self.issues += issues
    progress.update_completion! 65

    progress.update_completion! 99
  end

  def check_scope(scope, *attrs)
    issues = []
    scope.find_in_batches(batch_size: 100) do |batch|
      batch.each do |model|
        case model
          when AssessmentQuestion, Quizzes::QuizQuestion
            check_question(model) do |links|
              issues += links
            end
          else
            attrs.each do |attr|
              text = model.respond_to?(attr) && model[attr] || nil
              find_invalid_links(text) do |links|
                issues << {:id => model.id, :type => model.class.model_name.param_key, :attr => attr, :invalid_links => links}
              end
            end
        end
      end
    end
    issues
  end

  def check_question(question)
    links = []
    [:question_text, :correct_comments_html, :incorrect_comments_html, :neutral_comments_html, :more_comments_html].each do |field|
      find_invalid_links(question.question_data[field]) do |field_links|
        links += field_links
      end
    end

    (question.question_data[:answers] || []).each_with_index do |answer, i|
      [:html, :comments_html, :left_html].each do |field|
        find_invalid_links(answer[field]) do |field_links|
          links += field_links
        end
      end
    end

    if links.any?
      hash = {:name => question.question_data[:question_name]}.merge(:invalid_links => links)
      case question
        when AssessmentQuestion
          hash[:type] = :assessment_question
          hash[:content_url] = "/courses/#{self.course.id}/question_banks/#{question.assessment_question_bank_id}#question_#{question.id}_question_text"
        when Quizzes::QuizQuestion
          hash[:type] = :quiz_question
          hash[:content_url] = "/courses/#{self.course.id}/quizzes/#{question.quiz_id}/take?preview=1#question_#{question.id}"
      end
      issues << hash
    end

    yield links if links.any?
  end

  def find_invalid_links(html)
    links = []
    doc = Nokogiri::HTML(html || "")
    attrs = ['rel', 'href', 'src', 'data', 'value']

    doc.search("*").each do |node|
      attrs.each do |attr|
        url = node[attr]
        next unless url.present?
        if attr == 'value'
          next unless node['name'] && node['name'] == 'src'
        end

        find_invalid_link(url) do |invalid_link|
          links << invalid_link
        end
      end
    end

    yield links if links.any?
  end

  def find_invalid_link(url)
    if self.domain_regex && url.match(self.domain_regex)
      invalid_link = {:url => url}
      yield invalid_link
    end
  end
end
