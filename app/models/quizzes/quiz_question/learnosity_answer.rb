class Quizzes::QuizQuestion::LearnosityAnswer < Quizzes::QuizQuestion::UserAnswer

  def initialize(question_id, points_possible, answer_data)
    super(question_id, points_possible, answer_data)
    self.answer_details = ActiveSupport::JSON::decode(self.answer_details[:text]) rescue {}
  end

  def score
    begin
      score = self.answer_details['scores'][question_id.to_s]['score'].to_f
      max_score = self.answer_details['scores'][question_id.to_s]['max_score'].to_f
      max_score > 0 ? (((score / max_score) * self.points_possible).round(2)) : 0
    rescue
      super
    end
  end

end
