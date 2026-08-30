# A family's FIRE plan: pulls income, expenses, and investable portfolio
# from the family's real data, projects year-by-year to a FIRE date with tax
# drag (FirePlan::Projector + FirePlan::TaxEstimator), and stress-tests the
# same cashflow schedule with randomized returns (FirePlan::MonteCarlo).
# Nothing is persisted — every assumption travels as a query param, and any
# derived input can be overridden the same way.
class FirePlan
  include Monetizable

  monetize :portfolio, :gross_income, :annual_expenses, :fire_number

  FILING_STATUSES = %w[single married_filing_jointly].freeze

  # name => [default, min, max]. Clamping keeps hostile or fat-fingered
  # params from producing absurd math (a 900% return, a negative age).
  ASSUMPTION_BOUNDS = {
    current_age: [ 30, 16, 100 ],
    income_growth: [ 3.0, 0, 20 ],
    inflation: [ 3.0, 0, 20 ],
    expected_return: [ 7.0, 0, 20 ],
    volatility: [ 15.0, 0, 50 ],
    swr: [ 4.0, 1, 10 ],
    state_rate: [ 5.0, 0, 15 ],
    retirement_tax_rate: [ 10.0, 0, 50 ]
  }.freeze

  attr_reader :family, :filing_status

  def initialize(family:, assumptions: {})
    @family = family
    @raw = assumptions || {}
    @assumptions = ASSUMPTION_BOUNDS.to_h do |name, (default, min, max)|
      value = @raw[name].presence&.to_d || default.to_d
      [ name, value.clamp(min.to_d, max.to_d) ]
    end
    @filing_status = FILING_STATUSES.include?(@raw[:filing_status]) ? @raw[:filing_status] : "single"
  end

  def assumption(name) = @assumptions.fetch(name)

  # Derived from the family's data unless explicitly overridden. Medians
  # rather than averages so a one-off windfall or splurge month doesn't
  # skew the whole plan.
  def gross_income
    @gross_income ||= @raw[:gross_income].presence&.to_d || (income_statement.median_income(interval: "month").to_d * 12)
  end

  def annual_expenses
    @annual_expenses ||= @raw[:annual_expenses].presence&.to_d || (income_statement.median_expense(interval: "month").to_d * 12)
  end

  def portfolio
    @portfolio ||= @raw[:portfolio].presence&.to_d || (Investment.balance_money(family) + Crypto.balance_money(family))
  end

  def plannable?
    gross_income.positive? || portfolio.positive?
  end

  # The life events the family has planned. Inactive milestones are simply
  # not part of the plan.
  def milestones
    @milestones ||= family.fire_milestones.active.to_a
  end

  def projection
    @projection ||= build_projection(milestone_events)
  end

  # The same plan with every life event removed, so the UI can show what the
  # milestones actually cost (or bought) the family.
  def baseline_projection
    @baseline_projection ||= build_projection([])
  end

  # Positive means the milestones push FIRE later, negative means earlier.
  # Nil whenever either side never fires inside the horizon, since there is
  # nothing meaningful to subtract.
  def fire_age_delta
    return nil unless baseline_projection.fire_age && projection.fire_age

    projection.fire_age - baseline_projection.fire_age
  end

  # Stress-tests the deterministic plan's own cashflow schedule: same
  # contributions and withdrawals, randomized returns. This deliberately
  # uses the with-events projection — the point is to stress-test the real
  # plan, milestones included, not a baseline the family isn't living.
  def monte_carlo
    @monte_carlo ||= FirePlan::MonteCarlo.new(trials: 1000).simulate(
      portfolio: portfolio.to_f,
      cashflows: projection.rows.map { |row| row.savings.to_f },
      mean_return: assumption(:expected_return).to_f,
      volatility: assumption(:volatility).to_f
    )
  end

  def fire_number = projection.fire_number
  def fire_age = projection.fire_age
  def years_to_fire = projection.years_to_fire
  def fired_within_horizon? = projection.fired_within_horizon

  def currency
    family.currency
  end

  # Everything the projection chart draws, labels pre-formatted server-side:
  # the deterministic portfolio path plus the Monte Carlo percentile band.
  def chart_payload
    symbol = Money::Currency.new(currency).symbol
    {
      currency_symbol: symbol,
      fire_number: fire_number.to_f,
      fire_number_label: format_chart_money(fire_number),
      fire_age: fire_age,
      fire_age_delta: fire_age_delta,
      success_rate: monte_carlo.success_rate,
      # Only sent when there is something to compare against, so the chart
      # knows whether to draw the dashed "without your milestones" line.
      baseline: milestones.any? ? baseline_series : nil,
      rows: projection.rows.map.with_index do |row, i|
        band = monte_carlo.percentiles[i]
        {
          year: row.year,
          age: row.age,
          value: row.portfolio.to_f,
          value_formatted: format_chart_money(row.portfolio),
          fired: row.fired,
          p10: band&.dig(:p10),
          p90: band&.dig(:p90)
        }
      end
    }
  end

  private
    def build_projection(events)
      FirePlan::Projector.new(
        tax_estimator: tax_estimator,
        current_age: assumption(:current_age).to_i,
        portfolio: portfolio,
        gross_income: gross_income,
        annual_expenses: annual_expenses,
        income_growth: assumption(:income_growth),
        inflation: assumption(:inflation),
        expected_return: assumption(:expected_return),
        swr: assumption(:swr),
        retirement_tax_rate: assumption(:retirement_tax_rate),
        events: events
      ).project
    end

    # The projector is pure math and knows nothing about FireMilestone, so
    # the mapping lives here.
    def milestone_events
      milestones.map do |milestone|
        {
          start_age: milestone.start_age,
          end_age: milestone.end_age,
          one_time: milestone.one_time_amount,
          annual: milestone.annual_amount,
          affects: milestone.affects
        }
      end
    end

    def baseline_series
      baseline_projection.rows.map { |row| { year: row.year, value: row.portfolio.to_f } }
    end

    def tax_estimator
      FirePlan::TaxEstimator.new(filing_status: filing_status, state_rate: assumption(:state_rate))
    end

    def income_statement
      @income_statement ||= IncomeStatement.new(family, accounts: family.accounts.visible.included_in_reports)
    end

    def format_chart_money(value)
      Money.new(value, currency).format(precision: 0)
    end
end
