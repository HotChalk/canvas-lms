class ContentSearch

  TAG = "content_search"

  def initialize(search_text, account_ids)
    @search_text = search_text
    @account_ids = account_ids
  end

  def search_all
    begin
      @accounts = []
      @account_ids.split(",").each do |account_id|
        account = Account.find(account_id.to_i) rescue nil
        @accounts << account if account.present?
      end
      @accounts << Account.default if @accounts.empty?
      @accounts.uniq!

      @accounts.each do |account|
        search_assessment_questions(account)
        search_assignments(account)
        search_content_tags(account)
        search_courses(account)
        search_discussion_topics(account)
        search_quizzes(account)
        search_quiz_questions(account)
        search_wiki_pages(account)
      end
    rescue Exception => e
      Rails.logger.error "[CONTENT-SEARCH] Content search failed: #{e.inspect}"
    end
  end

  def output_hit(model, field, url)
    excerpt = ActionView::Base.new.excerpt(model.send(field).to_s, /#{@search_text}/, separator: ' ', radius: 3)
    Rails.logger.info "[CONTENT-SEARCH] Found: type=[#{model.class.name}], id=[#{model.id}], field=[#{field}], url=[#{url}], text=[#{excerpt.delete("\n")}]" unless excerpt.blank?
  end

  def search_assessment_questions(account)
    # AssessmentQuestion => [:question_data]
    account.assessment_questions.where("question_data LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
      url = ""
      output_hit(item, :question_data, url)
    end
    account.courses.active.each do |course|
      course.assessment_questions.where("question_data LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/question_banks/#{item.assessment_question_bank_id}"
        output_hit(item, :question_data, url)
      end
    end
  end

  def search_assignments(account)
    # Assignment => [:title, :description]
    account.courses.active.each do |course|
      course.active_assignments.where("title LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/assignments/#{item.id}"
        output_hit(item, :title, url)
      end
      course.active_assignments.where("description LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/assignments/#{item.id}"
        output_hit(item, :description, url)
      end
    end
  end

  def search_content_tags(account)
    # ContentTag => [:title, :url, :comments]
    account.courses.active.each do |course|
      course.active_context_modules.each do |context_module|
        context_module.content_tags.not_deleted.where("title LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
          url = "/courses/#{course.id}/modules"
          output_hit(item, :title, url)
        end
        context_module.content_tags.not_deleted.where("url LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
          url = "/courses/#{course.id}/modules"
          output_hit(item, :url, url)
        end
        context_module.content_tags.not_deleted.where("comments LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
          url = "/courses/#{course.id}/modules"
          output_hit(item, :comments, url)
        end
      end
    end
  end

  def search_courses(account)
    # Course => [:syllabus_body]
    account.courses.active.where("syllabus_body LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
      url = "/courses/#{item.id}/assignments/syllabus"
      output_hit(item, :syllabus_body, url)
    end
  end

  def search_discussion_topics(account)
    # DiscussionTopic => [:message]
    account.courses.active.each do |course|
      course.active_discussion_topics.where("message LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/discussion_topics/#{item.id}"
        output_hit(item, :message, url)
      end
    end
  end

  def search_quizzes(account)
    # Quizzes::Quiz => [:description, :quiz_data]
    account.courses.active.each do |course|
      course.active_quizzes.where("description LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/quizzes/#{item.id}"
        output_hit(item, :description, url)
      end
      course.active_quizzes.where("quiz_data LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/quizzes/#{item.id}"
        output_hit(item, :quiz_data, url)
      end
    end
  end

  def search_quiz_questions(account)
    # Quizzes::QuizQuestion => [:question_data]
    account.courses.active.each do |course|
      course.quiz_questions.where("question_data LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/quizzes/#{item.quiz.id}"
        output_hit(item, :question_data, url)
      end
    end
  end

  def search_wiki_pages(account)
    # WikiPage => [:body, :title]
    account.courses.active.each do |course|
      course.wiki_pages.not_deleted.where("body LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/pages/#{item.url}"
        output_hit(item, :body, url)
      end
      course.wiki_pages.not_deleted.where("title LIKE #{ActiveRecord::Base.connection.quote('%' + @search_text + '%')}").each do |item|
        url = "/courses/#{course.id}/pages/#{item.url}"
        output_hit(item, :title, url)
      end
    end
  end

end
