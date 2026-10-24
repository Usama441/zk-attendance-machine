class CreateParkingRequests < ActiveRecord::Migration[7.1]
  # Monthly parking sticker requests from the employee portal. Sticker prices (bike / car) are
  # set by an admin; each request keeps the price that applied when it was made.
  def change
    create_table :parking_requests do |t|
      t.references :employee, null: false, foreign_key: true
      t.date    :month, null: false
      t.string  :vehicle_type, null: false
      t.string  :vehicle_number, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string  :status, null: false, default: "pending"
      t.string  :reviewed_by
      t.datetime :reviewed_at
      t.string  :admin_note
      t.timestamps
    end
    add_index :parking_requests, %i[month status]

    add_column :app_settings, :parking_bike_price, :decimal, precision: 10, scale: 2, null: false, default: 700
    add_column :app_settings, :parking_car_price,  :decimal, precision: 10, scale: 2, null: false, default: 1500
  end
end
