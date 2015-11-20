module CourseLibrary::Settings

  def self.included(base)
    base.attr_accessible :course_library_settings
    base.serialize :course_library_settings, Hash
  end

  def set_cl_link(cl_id)
    if cl_id
      course_library_settings[:link_active] = true
      course_library_settings[:learning_object_id] = cl_id.to_i
    end
  end

  def is_cl_link_active
    return course_library_settings[:link_active] ? course_library_settings[:link_active] : false
  end

end
