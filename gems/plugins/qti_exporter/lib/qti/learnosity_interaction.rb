module Qti
class LearnosityInteraction < Qti::AssessmentItemConverter

  def initialize(opts)
    super(opts)
    @question[:answers] = []
    @question[:variables] = []
    @question[:question_type] = 'learnosity_question'
  end

  def parse_question_data
    @question[:question_text] = ''
    @doc.css('itemBody > div.html').each_with_index do |text, i|
      @question[:question_text] += text.text
    end
    @question
  end

end
end
