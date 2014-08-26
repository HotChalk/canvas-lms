Quizzes::QuizzesController.class_eval do

  alias :statistics_original :statistics
  def statistics
    statistics_original
    if @js_env[:quiz_reports] && @quiz.quiz_questions.any? { |q| q.question_data[:question_type] == 'learnosity_question' }
      @js_env[:quiz_reports] = {}
    end
  end

end