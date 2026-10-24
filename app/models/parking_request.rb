# frozen_string_literal: true

# A monthly parking sticker request (employee portal → Parking; admin → Parking). A sticker is
# always for the current month and expires when the month ends; the employee requests again in
# the new month. The price is copied from Settings when the request is made.
class ParkingRequest < ApplicationRecord
  VEHICLES = { "bike" => "Bike", "car" => "Car" }.freeze
  STATUSES = %w[pending approved rejected cancelled].freeze
  # Pakistani plate: 2–4 letters, a dash, 1–4 digits (e.g. LEM-334). Stored uppercase.
  PLATE = /\A[A-Z]{2,4}-\d{1,4}\z/

  belongs_to :employee

  before_validation :normalize

  validates :vehicle_type, inclusion: { in: VEHICLES.keys, message: "must be bike or car" }
  validates :vehicle_number, presence: true,
                             format: { with: PLATE, message: "should be letters, a dash and numbers, like LEM-334" }
  validates :status, inclusion: { in: STATUSES }
  validates :month, :price, presence: true
  validates :admin_note, length: { maximum: 255 }
  validate :current_month_only, on: :create
  validate :not_duplicate, on: :create

  scope :pending,   -> { where(status: "pending") }
  scope :approved,  -> { where(status: "approved") }
  scope :open,      -> { where(status: %w[pending approved]) }
  scope :for_month, ->(month) { where(month: month.to_date.beginning_of_month) }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def self.price_for(vehicle_type)
    settings = AppSetting.current
    vehicle_type == "car" ? settings.parking_car_price : settings.parking_bike_price
  end

  def vehicle_label = VEHICLES.fetch(vehicle_type, vehicle_type.to_s.humanize)
  def valid_until = month.end_of_month
  # An approved sticker from an earlier month has run out.
  def expired? = approved? && valid_until < Date.today
  def display_status = expired? ? "expired" : status

  def review!(decision, by:, note: nil)
    raise ArgumentError, "unknown decision" unless %w[approved rejected].include?(decision)
    raise ArgumentError, "a cancelled request cannot be reviewed" if cancelled?

    update!(status: decision, reviewed_by: by, reviewed_at: Time.current, admin_note: note.presence)
  end

  def cancel!
    raise ArgumentError, "only pending requests can be cancelled" unless pending?

    update!(status: "cancelled")
  end

  private

  def normalize
    # "lem 334", "LEM334", "lem-334" → "LEM-334"
    plate = vehicle_number.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    plate = "#{$1}-#{$2}" if plate =~ /\A([A-Z]+)(\d+)\z/
    self.vehicle_number = plate.presence
    self.month = month&.to_date&.beginning_of_month
    self.price ||= self.class.price_for(vehicle_type) if VEHICLES.key?(vehicle_type)
  end

  def current_month_only
    return if month.nil? || month == Date.today.beginning_of_month

    errors.add(:month, "must be the current month (#{Date.today.strftime('%B %Y')}) — request again next month")
  end

  def not_duplicate
    return if employee.nil? || month.nil? || vehicle_number.blank?
    return unless employee.parking_requests.open.where(month: month, vehicle_number: vehicle_number).exists?

    errors.add(:base, "You already have a request for #{vehicle_number} in #{month.strftime('%B %Y')}")
  end
end
