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

    # Find effective points possible for this question
    possible_points = self.points_possible
    quiz = Quizzes::QuizQuestion.find(self.question_id).try(:quiz) if self.question_id
    if quiz
      quiz.stored_questions.each do |item|
        if item[:questions] && item[:questions].any? {|q| q[:id] == self.question_id} # current item is a quiz group
          possible_points = item[:question_points]
        elsif !item[:questions] && item[:id] == self.question_id # current item is a regular question
          possible_points = item[:points_possible]
        end
      end
    end

    responses.each do |response|
      stats[:learnosity_responses] << {
        :user_id => response[:user_id],
        :points_awarded => (response[:points] rescue 0),
        :points_possible => possible_points
      }
    end

    @question_data.merge stats
  end

end