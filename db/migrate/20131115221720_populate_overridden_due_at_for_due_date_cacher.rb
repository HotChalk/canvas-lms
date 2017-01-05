class PopulateOverriddenDueAtForDueDateCacher < ActiveRecord::Migration[4.2]
  tag :postdeploy

  def self.up
    DataFixup::PopulateOverriddenDueAtForDueDateCacher.send_later_if_production(:run)
  end
end
