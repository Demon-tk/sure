class FirePlansController < ApplicationController
  # Every assumption travels as a query param — nothing is persisted, so
  # there is no model to strong-param against. FirePlan clamps and validates
  # each value itself; the controller only narrows the keys.
  ASSUMPTION_PARAMS = %i[
    current_age income_growth inflation expected_return volatility swr
    state_rate retirement_tax_rate filing_status
    gross_income annual_expenses portfolio
  ].freeze

  before_action :require_preview_features!

  def show
    @plan = FirePlan.new(family: Current.family, assumptions: fire_assumptions)

    @breadcrumbs = plan_breadcrumb_prefix + [ [ t(".title"), nil ] ]
  end

  private
    # Scalars only: a nested or array param (?swr[]=1) would reach FirePlan as
    # something that can't be coerced to a decimal. Blanks are dropped so an
    # emptied field falls back to the derived value rather than to zero.
    def fire_assumptions
      ASSUMPTION_PARAMS.each_with_object({}) do |key, assumptions|
        value = params[key]
        assumptions[key] = value.presence if value.is_a?(String)
      end.compact
    end
end
