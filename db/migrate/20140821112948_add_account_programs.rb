class AddAccountPrograms < ActiveRecord::Migration
  tag :predeploy

  def self.up
    # account programs table
    create_table :account_programs do |t|
      t.integer :account_id, :limit => 8, :null => false
      t.string :name, :null => false
    end

    add_index :account_programs, [:account_id]

    # include programs on courses
    add_column :courses, :account_program_id, :integer, :limit => 8
    add_index :courses, :account_program_id
  end

  def self.down
    remove_index :courses, :account_program_id
    remove_column :courses, :account_program_id

    remove_index :account_programs, [:account_id]
    drop_table :account_programs
  end
end