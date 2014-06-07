module Learnosity

  def self.config
    Canvas::Plugin.find('learnosity').settings || {}
  end

end