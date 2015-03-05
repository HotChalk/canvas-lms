class FixAddRoleOverridesForManageAnnouncements < ActiveRecord::Migration
  tag :postdeploy
  disable_ddl_transaction!

  def self.up
    DataFixup::AddRoleOverridesForNewPermission.send_later_if_production(:run, :moderate_forum, :manage_announcements)
  end

  def down
  end
end
