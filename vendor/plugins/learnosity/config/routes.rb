CanvasRails::Application.routes.draw do
  scope(controller: 'quizzes/quiz_questions_display') do
    get "courses/:course_id/quizzes/:quiz_id/questions/:id/display", action: :show
  end
end
