class FixAssignmentOverridesForSectionIds < ActiveRecord::Migration
  tag :postdeploy
  disable_ddl_transaction!

  def up
    DataFixup::SyncAssignmentOverridesForSectionIds.send_later_if_production(:run)
  end

end
