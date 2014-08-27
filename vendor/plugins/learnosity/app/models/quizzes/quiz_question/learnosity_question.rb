class Quizzes::QuizQuestion::LearnosityQuestion < Quizzes::QuizQuestion::Base

  def requires_manual_scoring?(user_answer)
    !user_answer.answer_details['scores'] || user_answer.answer_details['scores'].empty?
  end

  def correct_answer_parts(user_answer)
    scores = user_answer.answer_details['scores']
    return nil unless scores && !scores.empty? && scores["#{self.question_id}"] && scores["#{self.question_id}"]['score']
    scores = scores["#{self.question_id}"]
    scores['max_score'] == scores['score']
  end

  def score_question(answer_data, user_answer=nil)
    user_answer = Quizzes::QuizQuestion::LearnosityAnswer.new(self.question_id, self.points_possible, answer_data)
    super(answer_data, user_answer)
  end

  def stats(responses)
    stats = {:learnosity_responses => []}

    responses.each do |response|
      stats[:learnosity_responses] << {
        :user_id => response[:user_id],
        :points_awarded => (response[:points] rescue 0),
      }
    end

    @question_data.merge stats
  end

end