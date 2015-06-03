AssessmentQuestion.class_eval do

  AssessmentQuestion::ALL_QUESTION_TYPES.push("learnosity_question") unless AssessmentQuestion::ALL_QUESTION_TYPES.include?("learnosity_question")

end