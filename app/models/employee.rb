class Employee < ApplicationRecord
  PORTAL_PASSWORD_MIN = 4

  has_many :punches, dependent: :destroy
  has_many :leave_requests, dependent: :destroy
  has_many :comments, class_name: "EmployeeComment", dependent: :destroy
  has_many :parking_requests, dependent: :destroy
  has_one :photo, class_name: "EmployeePhoto", dependent: :destroy

  # Portal password is optional: employees without one simply cannot use the self-service portal.
  has_secure_password validations: false

  # Sign-in role: employees get the self-service portal, admins get the full app.
  enum :role, { employee: 0, admin: 1 }, default: :employee

  validates :uid, presence: true, uniqueness: true
  validates :monthly_salary, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000_000 }
  validates :password, length: { minimum: PORTAL_PASSWORD_MIN }, allow_nil: true
  validates :portal_username, uniqueness: true, allow_nil: true, length: { maximum: 50 },
                              format: { with: /\A[a-z0-9._-]+\z/, message: "can only use letters, numbers, dots, dashes and underscores" }

  before_validation { self.portal_username = portal_username.to_s.strip.downcase.presence }

  # Left out of "All employees" exports: hidden in Settings, or deactivated on the machine.
  scope :exportable, -> { where(hidden_from_export: false, device_enabled: true) }

  # Device enable/disable status is managed by the app (Deactivate / Activate in
  # Settings → Machine access), not re-derived from the device: this firmware has no
  # reliable per-user "disabled" flag to read back, and deactivation removes the
  # person's credentials rather than setting a flag. Kept as a no-op so the refresh
  # endpoint (which also pulls names and photos) keeps working. Returns 0.
  def self.refresh_device_status!(_device_users)
    0
  end

  # Portal sign-in: by username (e.g. "usama.arshad"), or by employee ID for those without one.
  def self.find_for_portal(login)
    login = login.to_s.strip.downcase
    return nil if login.empty?

    find_by(portal_username: login) || (find_by(uid: login.to_i) if login.match?(/\A\d+\z/))
  end

  # Suggested portal username from the name: "Usama Arshad" → "usama.arshad".
  def suggested_portal_username = name.to_s.downcase.scan(/[a-z0-9]+/).join(".")

  def label
    "#{name} (ID #{uid})"
  end

  def initials
    name.to_s.split.map(&:first).first(2).join.upcase.presence || "#"
  end

  def portal_enabled?
    password_digest.present?
  end
end
