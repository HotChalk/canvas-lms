class Quizzes::QuizQuestion::LearnosityAnswer < Quizzes::QuizQuestion::UserAnswer

  def initialize(question_id, points_possible, answer_data)
    super(question_id, points_possible, answer_data)
    self.answer_details = ActiveSupport::JSON::decode(self.answer_details[:text]) rescue {}
  end

  def score
    self.answer_details['scores'][question_id.to_s]['score'] rescue super
  end

end
