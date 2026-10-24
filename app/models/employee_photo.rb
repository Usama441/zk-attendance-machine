class EmployeePhoto < ApplicationRecord
  belongs_to :employee

  # Replace the stored photos with the machine's ({ "1100" => jpeg bytes }). Photos of
  # people no longer on the machine's photo list are removed. Returns the number stored.
  def self.sync!(photos_by_user_id)
    now = Time.current
    ids = Employee.where(uid: photos_by_user_id.keys.map(&:to_i)).pluck(:uid, :id).to_h
    transaction do
      where.not(employee_id: ids.values).delete_all
      ids.each do |uid, employee_id|
        photo = find_or_initialize_by(employee_id: employee_id)
        photo.data = photos_by_user_id[uid.to_s]
        photo.fetched_at = now if photo.new_record? || photo.data_changed?
        photo.save! if photo.changed?
      end
    end
    ids.size
  end
end
