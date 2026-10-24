class CreateEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :employees do |t|
      t.integer :uid, null: false
      t.string  :name
      t.timestamps
    end
    add_index :employees, :uid, unique: true
  end
end
