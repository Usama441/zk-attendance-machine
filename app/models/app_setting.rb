class AppSetting < ApplicationRecord
  GLOBAL_KEY = "global"
  CONNECTION_FIELDS = %w[device_host device_port device_open_timeout device_read_timeout].freeze
  SDK_FIELDS = %w[device_sdk_port device_comm_key].freeze
  # Employee portal pages the admin can hide, in menu order. Account (password, sign-out) is
  # always available, so an employee is never left with nowhere to land.
  PORTAL_PAGES = {
    "home" => "Home",
    "attendance" => "Attendance",
    "salary" => "Salary",
    "leaves" => "Leaves",
    "parking" => "Parking"
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :sync_interval_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 1_440 }
  validates :sync_lookback_days,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }
  validates :device_name, presence: true, length: { maximum: 80 }
  validates :device_host, presence: true, length: { maximum: 253 },
                          format: { with: /\A[a-zA-Z0-9.-]+\z/, message: "must be an IP address or hostname" }
  validates :device_port,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535 }
  validates :device_sdk_port,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535 }
  validates :device_comm_key,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 999_999 }
  validates :device_open_timeout, :device_read_timeout,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }

  validates :parking_bike_price, :parking_car_price,
            numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000 }

  def self.current
    find_or_create_by!(key: GLOBAL_KEY)
  end

  def portal_page_visible?(page)
    !hidden_portal_pages.include?(page.to_s)
  end

  def auto_sync_due?(now = Time.current)
    auto_sync_enabled? && (last_sync_at.nil? || last_sync_at <= sync_interval_minutes.minutes.ago(now))
  end

  def auto_range(today = Date.current)
    [(today - (sync_lookback_days - 1)), today]
  end

  def connection_configuration_changed?
    CONNECTION_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
  end

  def zk_client(username:, password:)
    ZkClient.new(
      host: device_host,
      port: device_port,
      username: username,
      password: password,
      open_timeout: device_open_timeout,
      read_timeout: device_read_timeout
    )
  end

  # Binary SDK client (port 4370) — needed to enable/disable users on the machine.
  def zk_sdk_client
    ZkSdkClient.new(host: device_host, port: device_sdk_port, comm_key: device_comm_key,
                    timeout: [device_read_timeout, 10].max)
  end
end
