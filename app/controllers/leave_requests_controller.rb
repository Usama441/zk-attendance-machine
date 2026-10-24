# frozen_string_literal: true

# Admin side of leave requests: review (approve / reject) what employees applied for, or add
# a leave on someone's behalf (approved straight away).
# Approved paid leave is not counted as absent; approved unpaid leave is deducted like an absence.
class LeaveRequestsController < ApplicationController
  FILTERS = %w[pending approved rejected cancelled all].freeze

  def index
    @filter = FILTERS.include?(params[:status]) ? params[:status] : "pending"
    # Every status is loaded; the table's filter pills switch between them (starting on @filter).
    @leaves = LeaveRequest.includes(:employee).order(start_date: :desc, created_at: :desc).limit(1000)
    @employees = Employee.where(device_enabled: true).order(:name)
    @leave = LeaveRequest.new(start_date: Date.today, end_date: Date.today)
  end

  # POST /leaves — an admin adds a leave for an employee (e.g. called in sick, no portal access).
  def create
    leave = LeaveRequest.new(leave_params.merge(status: "approved", reviewed_by: current_admin,
                                                reviewed_at: Time.current, admin_note: "Added by admin"))
    leave.save!
    redirect_to leave_requests_path(status: "approved"),
                notice: "#{leave.type_label} added for #{leave.employee.name} (#{leave_label(leave)}, #{leave.days} day(s)), approved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to leave_requests_path, alert: "Could not add leave: #{e.record.errors.full_messages.to_sentence}"
  end

  # POST /leaves/:id/review  decision=approved|rejected
  def review
    leave = LeaveRequest.find(params[:id])
    leave.review!(params[:decision].to_s, by: current_admin, note: params[:admin_note])
    redirect_to leave_requests_path(status: params[:status]),
                notice: "#{leave.employee.name}'s leave (#{leave_label(leave)}) #{leave.status}."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to leave_requests_path(status: params[:status]), alert: "Could not update: #{e.message}"
  end

  private

  def leave_params
    params.require(:leave_request).permit(:employee_id, :leave_type, :start_date, :end_date, :reason)
  end

  def leave_label(leave)
    "#{leave.start_date.strftime('%d %b')}#{" – #{leave.end_date.strftime('%d %b')}" if leave.days > 1}"
  end
end
