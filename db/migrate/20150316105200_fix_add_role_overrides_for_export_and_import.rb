class FixAddRoleOverridesForExportAndImport < ActiveRecord::Migration
  tag :postdeploy
  disable_ddl_transaction!

  def self.up
    DataFixup::AddRoleOverridesForNewPermission.send_later_if_production(:run, :read_course_content, :export_course_content)
    DataFixup::AddRoleOverridesForNewPermission.send_later_if_production(:run, :read_course_content, :import_course_content)
  end

  def down
  end
end
