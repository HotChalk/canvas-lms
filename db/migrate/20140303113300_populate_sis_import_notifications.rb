class PopulateSisImportNotifications < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    return unless Shard.current == Shard.default
    Canvas::MessageHelper.create_notification({
      name: 'New User Registration',
      delay_for: 0,
      category: 'Registration'
    })
  end

  def self.down
    return unless Shard.current == Shard.default
    Notification.find_by_name('New User Registration').try(:destroy)
  end
end
