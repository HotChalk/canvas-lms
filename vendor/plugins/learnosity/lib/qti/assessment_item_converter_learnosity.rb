Qti::AssessmentItemConverter.class_eval do

  self.singleton_class.send(:alias_method, :create_instructure_question_original, :create_instructure_question)
  def self.create_instructure_question(opts)
    extend Canvas::Migration::XMLHelper
    manifest_node = opts[:manifest_node]
    if manifest_node
      if type = get_node_att(manifest_node,'instructureMetadata instructureField[name=question_type]', 'value')
        if type.downcase == 'learnosity_question'
          opts[:interaction_type] = 'learnosity_question'
          opts[:custom_type] = 'learnosity_question'
          return LearnosityInteraction.new(opts).create_instructure_question
        end
      end
    end
    self.create_instructure_question_original(opts)
  end

end

