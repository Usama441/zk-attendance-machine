# frozen_string_literal: true

# Admin: late cut-off times (Settings → Late time). Each rule applies from its date until the
# next rule, so changing the office timing never rewrites earlier months.
class LateRulesController < ApplicationController
  def index
    @rules = LateRule.order(effective_from: :desc).to_a
    @today_cutoff = LateRule.schedule.cutoff(Date.today)
  end

  # POST /settings/late
  def create
    rule = LateRule.new(rule_params)
    if rule.save
      redirect_to late_rules_path, notice: "From #{rule.effective_from.strftime('%d %b %Y')}, late is at or after #{rule.late_at}."
    else
      redirect_to late_rules_path, alert: rule.errors.full_messages.to_sentence
    end
  end

  # POST /settings/late/:id
  def update
    rule = LateRule.find(params[:id])
    if rule.update(rule_params)
      redirect_to late_rules_path, notice: "Saved: from #{rule.effective_from.strftime('%d %b %Y')}, late at #{rule.late_at}."
    else
      redirect_to late_rules_path, alert: rule.errors.full_messages.to_sentence
    end
  end

  # POST /settings/late/:id/delete
  def destroy
    if LateRule.count <= 1
      redirect_to late_rules_path, alert: "Keep at least one late time."
    else
      LateRule.find(params[:id]).destroy!
      redirect_to late_rules_path, notice: "Late time removed."
    end
  end

  private

  def rule_params = params.permit(:effective_from, :late_at)
end
