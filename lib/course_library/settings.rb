module CourseLibrary::Settings
  attr_accessor :settings

  def self.included(base)
    base.serialize :settings, Hash
  end

end
