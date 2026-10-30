class LeaveRequest < ApplicationRecord
  TYPES = {
    "casual" => "Casual leave",
    "sick"   => "Sick leave",
    "annual" => "Annual leave",
    "unpaid" => "Unpaid leave"
  }.freeze
  STATUSES = %w[pending approved rejected cancelled].freeze
  MAX_DAYS = 60

  belongs_to :employee

  validates :leave_type, inclusion: { in: TYPES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validates :reason, presence: true, length: { maximum: 500 }
  validates :admin_note, length: { maximum: 255 }
  validate :dates_in_order
  validate :no_overlap, on: :create

  scope :pending,     -> { where(status: "pending") }
  scope :open,        -> { where(status: %w[pending approved]) }
  scope :overlapping, ->(from, to) { where("start_date <= ? AND end_date >= ?", to, from) }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def unpaid? = leave_type == "unpaid"
  def type_label = TYPES.fetch(leave_type, leave_type.to_s.humanize)
  def covers?(date) = start_date <= date && date <= end_date
  def days = (end_date - start_date).to_i + 1

  # An admin approves or rejects; a decision can be changed later (e.g. approved by mistake).
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

  def dates_in_order
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must not be before the start date") if end_date < start_date
    errors.add(:base, "A request can cover at most #{MAX_DAYS} days") if days > MAX_DAYS
  end

  def no_overlap
    return if start_date.blank? || end_date.blank? || employee.nil?
    clash = employee.leave_requests.open.overlapping(start_date, end_date).order(:start_date).first
    return unless clash

    dates = clash.start_date.strftime("%d %b %Y")
    dates += " – #{clash.end_date.strftime('%d %b %Y')}" if clash.days > 1
    errors.add(:base, "#{employee.name} already has #{clash.status} #{clash.type_label.downcase} on #{dates}")
  end
end
