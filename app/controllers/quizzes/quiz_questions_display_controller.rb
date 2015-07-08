class Quizzes::QuizQuestionsDisplayController < ApplicationController
  include Api::V1::QuizQuestion
  include Filters::Quizzes

  before_filter :require_context, :require_quiz
  before_filter :require_question, :only => [:show]

  def show
    if authorized_action(@quiz, @current_user, :update) && @question.question_data[:question_type] == 'learnosity_question'
      render :json => learnosity_json(:question => @question.question_data, :answers => nil, :assessing => false, :assessment_results => nil, :display_correct_answers => false)
    end
  end

  private

  def require_question
    unless @question = @quiz.quiz_questions.active.find(params[:id])
      raise ActiveRecord::RecordNotFound.new('Quiz Question not found')
    end
  end
end

