# taking out the Ember Data menu option on every course.
# Ember Data menu option id = 17
module DataFixup
  module FixEmberDataFromMenuYaml
    def self.run
      Course.active.find_each(batch_size: 1000) do |course|
        tabs = course[:tab_configuration]
        if !tabs.nil? && !tabs.empty?
          tabs = tabs.reject{|t| (t.class == Hash)? t["id"].to_i == 17 : t[:id].to_i == 17}
          course[:tab_configuration] = tabs
          course.save
        end
      end
    end
  end
end