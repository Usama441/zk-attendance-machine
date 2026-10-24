class CreateEmployeePhotos < ActiveRecord::Migration[7.1]
  # User photos pulled from the machine (Menu → User Mng → Edit → Photo), one JPEG per employee.
  # Kept out of the employees table so loading employee lists never drags the image bytes along.
  def change
    create_table :employee_photos do |t|
      t.references :employee, null: false, foreign_key: true, index: { unique: true }
      t.binary :data, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
  end
end
