module Api::V1::CourseSection
  def course_sections_json(sections)
    sections.map do |section|
      section_json = section.attributes.slice *%w(id name)
      section_json
    end
  end
end