# Deterministic year-by-year FIRE projection. This is a planning-grade
# model, not ledger accounting: it compounds annually (one growth step
# applied at the end of each year, no intra-year cashflow timing), and
# every percent argument is an annual rate in whole-percent units
# (7.0 means 7% per year, not 0.07).
#
# Money is carried as unrounded BigDecimal through the accumulation loop
# and only rounded to cents when a Row is materialized, so rounding never
# feeds back into the next year's balance.
class FirePlan::Projector
  DEFAULT_SWR = BigDecimal(4)
  # A 100% retirement tax rate would make the withdrawal gross-up divide by
  # zero, so the rate is held strictly below 100.
  MAX_RETIREMENT_TAX_RATE = BigDecimal(99)

  Row = Data.define(:year, :age, :gross_income, :taxes, :expenses, :savings, :portfolio, :fire_number, :fired) do
    def fired? = fired
  end

  Projection = Data.define(:rows, :fire_age, :fire_year, :years_to_fire, :fire_number, :fired_within_horizon) do
    def fired_within_horizon? = fired_within_horizon
  end

  # tax_estimator is injected and only has to respond to
  # `estimate(gross_income:)` returning an object with a `#total`, which
  # keeps this class independent of any particular tax implementation.
  def initialize(
    tax_estimator:,
    current_age:,
    portfolio:,
    gross_income:,
    annual_expenses:,
    income_growth: 3.0,
    inflation: 3.0,
    expected_return: 7.0,
    swr: 4.0,
    retirement_tax_rate: 10.0,
    horizon_age: 90
  )
    @tax_estimator = tax_estimator
    @current_age = current_age.to_i
    @portfolio = decimal(portfolio)
    @gross_income = decimal(gross_income)
    @annual_expenses = decimal(annual_expenses)
    @income_growth = decimal(income_growth)
    @inflation = decimal(inflation)
    @expected_return = decimal(expected_return)
    @retirement_tax_rate = decimal(retirement_tax_rate).clamp(BigDecimal(0), MAX_RETIREMENT_TAX_RATE)

    # A non-positive safe withdrawal rate has no meaning (and would divide
    # by zero), so fall back to the 4% rule.
    swr = decimal(swr)
    @swr = swr.positive? ? swr : DEFAULT_SWR

    # A horizon at or before the current age still projects one year.
    @horizon_age = [ horizon_age.to_i, @current_age ].max
  end

  def project
    @project ||= build_projection
  end

  private

    def build_projection
      start_year = Date.current.year
      portfolio = @portfolio
      income = @gross_income
      fire_index = nil
      rows = []

      (0..(@horizon_age - @current_age)).each do |offset|
        expenses = expenses_for(offset)
        fire_number = fire_number_for(expenses)
        retired = !fire_index.nil?

        if retired
          gross_income = BigDecimal(0)
          # The retirement tax rate is a gross-up on the withdrawal: the
          # portfolio has to fund the spending *and* the tax on it.
          withdrawal = expenses / (1 - (@retirement_tax_rate / 100))
          taxes = withdrawal - expenses
          savings = -withdrawal
        else
          gross_income = income
          taxes = decimal(@tax_estimator.estimate(gross_income: gross_income).total)
          savings = gross_income - taxes - expenses
        end

        portfolio = (portfolio * (1 + (@expected_return / 100))) + savings
        # A portfolio cannot go below zero; once depleted it stays there
        # until positive savings rebuild it.
        portfolio = BigDecimal(0) if portfolio.negative?

        # FIRE is checked against *next* year's target, because that is the
        # number the portfolio actually has to cover once the paychecks stop.
        fire_index = offset if fire_index.nil? && portfolio >= fire_number_for(expenses_for(offset + 1))

        rows << Row.new(
          year: start_year + offset,
          age: @current_age + offset,
          gross_income: money(gross_income),
          taxes: money(taxes),
          expenses: money(expenses),
          savings: money(savings),
          portfolio: money(portfolio),
          fire_number: money(fire_number),
          fired: !fire_index.nil?
        )

        income *= (1 + (@income_growth / 100)) unless retired
      end

      build_summary(rows, fire_index, start_year)
    end

    def build_summary(rows, fire_index, start_year)
      if fire_index.nil?
        Projection.new(
          rows: rows,
          fire_age: nil,
          fire_year: nil,
          years_to_fire: nil,
          fire_number: rows.last.fire_number,
          fired_within_horizon: false
        )
      else
        Projection.new(
          rows: rows,
          fire_age: @current_age + fire_index,
          fire_year: start_year + fire_index,
          # The firing year is itself a full working year, so it counts.
          years_to_fire: fire_index + 1,
          fire_number: rows[fire_index].fire_number,
          fired_within_horizon: true
        )
      end
    end

    def expenses_for(offset)
      @annual_expenses * ((1 + (@inflation / 100))**offset)
    end

    # The target inflates with expenses, so each year is measured against the
    # number that year's spending actually requires.
    def fire_number_for(expenses)
      expenses / (@swr / 100)
    end

    def money(value)
      value.round(2)
    end

    def decimal(value)
      value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
    end
end
