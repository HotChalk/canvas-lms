require File.join(File.dirname(__FILE__), 'app/models/quizzes/quiz_question/learnosity_question')
require File.join(File.dirname(__FILE__), 'app/models/quizzes/quiz_question/learnosity_answer')
require File.join(File.dirname(__FILE__), 'app/models/quizzes/quiz_question/question_data')

Rails.configuration.to_prepare do
  Canvas::Plugin.register :learnosity, nil, {
    :name => proc { I18n.t('plugins.learnosity.name', 'Learnosity') },
    :website => 'http://www.hotchalk.com',
    :author => 'Hotchalk',
    :author_website => 'http://www.hotchalk.com',
    :version => '1.0.0',
    :description => proc { t('plugins.learnosity.description', 'Learnosity question delivery') },
    :settings_partial => 'plugins/learnosity_settings',
    :settings => {
        :consumer_key => nil,
        :consumer_secret => nil,
        :domain => nil
    }
  }
  ActionView::Base.send(:include, QuizzesHelperLearnosity)
  require File.join(File.dirname(__FILE__), 'app/models/assessment_question')
  require File.join(File.dirname(__FILE__), 'app/models/importers/assessment_question_importer')
  require File.join(File.dirname(__FILE__), 'lib/qti/learnosity_interaction')
  require File.join(File.dirname(__FILE__), 'lib/qti/assessment_item_converter_learnosity')
  require File.join(File.dirname(__FILE__), 'app/controllers/quizzes/quizzes_controller')
  require File.join(File.dirname(__FILE__), 'app/controllers/quizzes/quiz_questions_display_controller')
end
