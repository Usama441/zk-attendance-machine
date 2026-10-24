class AddCorrectionsToPunches < ActiveRecord::Migration[7.1]
  def change
    add_column :punches, :source,     :string,  null: false, default: "device"
    add_column :punches, :voided,     :boolean, null: false, default: false
    add_column :punches, :note,       :string
    add_column :punches, :created_by, :string
  end
end
