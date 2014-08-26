module QuizzesHelperLearnosity
  include QuizzesHelper

  alias :answer_type_original :answer_type
  def answer_type(question)
    if question && question[:question_type] == "learnosity_question"
      return QuestionType.new(
        "learnosity_question",
        "learnosity",
        "none",
        "learnosity",
        false,
        false
      )
    end
    answer_type_original(question)
  end

  def learnosity_question(options)
    question = hash_get(options, :question)
    question_text = hash_get(question, :question_text)
    answers = hash_get(options, :answers)
    state = learnosity_state(options)
    question_data = ActiveSupport::JSON::decode(question_text) rescue {}
    question_data[:response_id] = "#{question[:id]}"
    @response_id = "#{question[:id]}"
    @learnosity_request = learnosity_request.merge!({
        :state => state,
        :questions => [question_data]
    })
    if ['resume', 'review'].include? state
      @learnosity_request[:responses] = answers || {}
    end
    render :partial => 'quizzes/quizzes/learnosity_question'
  end

  def learnosity_request
    @plugin ||= Canvas::Plugin.find('learnosity')
    @consumer_key ||= @plugin.setting(:consumer_key)
    @consumer_secret ||= @plugin.setting(:consumer_secret)
    @domain ||= @plugin.setting(:domain)
    timestamp = Time.now.utc.strftime('%Y%m%d-%H%M')
    sha256 = Digest::SHA256.new
    sha256.update("#{@consumer_key}_#{@domain}_#{timestamp}_#{@current_user.uuid}_#{@consumer_secret}")
    signature = sha256.hexdigest
    return {
        :consumer_key => @consumer_key,
        :timestamp => timestamp,
        :signature => signature,
        :user_id => @current_user.uuid,
        :type => "local_practice"
    }
  end

  def learnosity_state(options)
    answers = hash_get(options, :answers)
    assessing = hash_get(options, :assessing)
    assessment_results = hash_get(options, :assessment_results)
    if assessing
      answers.nil? ? 'initial' : 'resume'
    elsif assessment_results
      'review'
    else
      'preview'
    end
  end

end