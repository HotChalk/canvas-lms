require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe QuizQuestionRegrade do

  describe "relationships" do

    it "belongs to a quiz_question" do
      QuizQuestionRegrade.new.should respond_to :quiz_question
    end

    it "belongs to a quiz_regrade" do
      QuizQuestionRegrade.new.should respond_to :quiz_regrade
    end
  end

  describe "validations" do

    it "validates the presence of quiz_question_id & quiz_regrade_id" do
      QuizQuestionRegrade.new.should_not be_valid
      QuizQuestionRegrade.new(quiz_question_id: 1, quiz_regrade_id: 1).should be_valid
    end
  end

  describe "#question_data" do
    it "should delegate to quiz question" do
      question = QuizQuestion.new
      question.stubs(:question_data => "foo")

      qq_regrade = QuizQuestionRegrade.new
      qq_regrade.quiz_question = question
      qq_regrade.question_data.should == "foo"
    end
  end
end
