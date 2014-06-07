Quizzes::QuizQuestion::QuestionData.class_eval do

  alias :question_types_original :question_types
  def question_types
    @question_types |= [:learnosity]
  end

end