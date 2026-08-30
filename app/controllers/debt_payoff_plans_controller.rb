class DebtPayoffPlansController < ApplicationController
  before_action :require_preview_features!

  def show
    @plan = DebtPayoffPlan.new(
      family: Current.family,
      user: Current.user,
      strategy: params[:strategy],
      extra_payment: params[:extra_payment],
      expected_return: params[:expected_return],
      overrides: parsed_overrides
    )

    @breadcrumbs = plan_breadcrumb_prefix + [ [ t(".title"), nil ] ]
  end

  private
    # overrides[<account_id>][rate|minimum_payment] query params for debts
    # whose accountable can't supply a rate or minimum. Values stay in the
    # URL — nothing is persisted.
    def parsed_overrides
      raw = params[:overrides]
      return {} unless raw.is_a?(ActionController::Parameters)

      raw.each_pair.with_object({}) do |(account_id, values), overrides|
        next unless values.is_a?(ActionController::Parameters)

        overrides[account_id.to_s] = {
          rate: values[:rate].presence,
          minimum_payment: values[:minimum_payment].presence
        }.compact
      end
    end
end
