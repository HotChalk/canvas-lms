Importers::AssessmentQuestionImporter.class_eval do

  # Please keep this method in sync with the original AssessmentQuestionImporter version.
  # Not much DRY-ness here, so feel free to optimize if there is a better implementation option.
  self.singleton_class.send(:alias_method, :prep_for_import_original, :prep_for_import)
  def self.prep_for_import(hash, context, migration=nil)
    return hash if hash[:prepped_for_import]
    hash[:missing_links] = {}
    fields_to_convert = [:question_text, :correct_comments_html, :incorrect_comments_html, :neutral_comments_html, :more_comments_html]
    if hash[:question_type] == 'learnosity_question'
      fields_to_convert.delete :question_text # do not HTML-convert Learnosity questions
    end
    fields_to_convert.each do |field|
      hash[:missing_links][field] = []
      if hash[field].present?
        hash[field] = ImportedHtmlConverter.convert(hash[field], context, migration, {:remove_outer_nodes_if_one_child => true}) do |warn, link|
          hash[:missing_links][field] << link if warn == :missing_link
        end
      end
    end
    [:correct_comments, :incorrect_comments, :neutral_comments, :more_comments].each do |field|
      html_field = "#{field}_html".to_sym
      if hash[field].present? && hash[field] == hash[html_field]
        hash.delete(html_field)
      end
    end
    hash[:answers].each_with_index do |answer, i|
      [:html, :comments_html, :left_html].each do |field|
        key = "answer #{i} #{field}"
        hash[:missing_links][key] = []
        if answer[field].present?
          answer[field] = ImportedHtmlConverter.convert(answer[field], context, migration, {:remove_outer_nodes_if_one_child => true}) do |warn, link|
            hash[:missing_links][key] << link if warn == :missing_link
          end
        end
      end
      if answer[:comments].present? && answer[:comments] == answer[:comments_html]
        answer.delete(:comments_html)
      end
    end if hash[:answers]
    hash[:prepped_for_import] = true
    hash
  end

end
