class FixEmberDataFromMenuYaml < ActiveRecord::Migration
  tag :postdeploy

  def up
    DataFixup::FixEmberDataFromMenuYaml.send_later_if_production(:run)
  end

  def down
  end
end
