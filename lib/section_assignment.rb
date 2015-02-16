module SectionAssignment

  def assigned_to_section?
    if (self.is_a?(Assignment) || self.is_a?(DiscussionTopic)) && self[:course_section_id] #|| Quizzes::Quiz.class_names.include?(self.class_name)
      self.course_section_id.present?
    else
      false
    end
  end

end
