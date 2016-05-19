# taking out the Ember Data menu option on every course.
# Ember Data menu option id = 17
module DataFixup
  module FixEmberDataFromMenuYaml
    def self.run
      Course.active.find_each(batch_size: 1000) do |course|
        tabs = course[:tab_configuration]
        if !tabs.nil? && !tabs.empty?
          tabs_tmp = tabs
          find_tab = nil
          tabs.each do |t|
            if t.class == Hash
              if t["id"].to_i == 17
                find_tab = t
                break
              end
            end
            if t.class == ActiveSupport::HashWithIndifferentAccess
              if t[:id].to_i == 17
                find_tab = t
                break
              end
            end
          end
          tabs_tmp.delete(find_tab)
          course[:tab_configuration] = tabs_tmp
          # course.save
        end
      end
    end
  end
end