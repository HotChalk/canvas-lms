class FixOnlyVisibleToOverridesForDiscussionTopics < ActiveRecord::Migration
  tag :postdeploy
  disable_ddl_transaction!

  def up
    DataFixup::FixOnlyVisibleToOverridesForDiscussionTopics.send_later_if_production(:run)
  end

end
