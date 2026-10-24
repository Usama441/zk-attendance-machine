# frozen_string_literal: true

# Admin: comments on employees for a date range. They fill the Comments column of the Excel
# export and are deleted automatically the day after their end date.
class EmployeeCommentsController < ApplicationController
  def index
    EmployeeComment.purge_expired!
    @comments  = EmployeeComment.includes(:employee).order(:starts_on, :id).to_a
    @employees = Employee.order(Arel.sql("LOWER(name)"), :uid)
  end

  # POST /comments
  def create
    comment = EmployeeComment.new(comment_params.merge(created_by: current_admin))
    if comment.save
      redirect_to employee_comments_path, notice: "Comment added for #{comment.employee.name}."
    else
      redirect_to employee_comments_path, alert: comment.errors.full_messages.to_sentence
    end
  end

  # POST /comments/:id
  def update
    comment = EmployeeComment.find(params[:id])
    if comment.update(comment_params.except(:employee_id))
      redirect_to employee_comments_path, notice: "Comment for #{comment.employee.name} saved."
    else
      redirect_to employee_comments_path, alert: comment.errors.full_messages.to_sentence
    end
  end

  # POST /comments/:id/delete
  def destroy
    comment = EmployeeComment.find(params[:id])
    comment.destroy!
    redirect_to employee_comments_path, notice: "Comment for #{comment.employee.name} deleted."
  end

  private

  def comment_params = params.permit(:employee_id, :body, :starts_on, :ends_on)
end
