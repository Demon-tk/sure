# Deterministic year-by-year FIRE projection. This is a planning-grade
# model, not ledger accounting: it compounds annually (one growth step
# applied at the end of each year, no intra-year cashflow timing), and
# every percent argument is an annual rate in whole-percent units
# (7.0 means 7% per year, not 0.07).
#
# Money is carried as unrounded BigDecimal through the accumulation loop
# and only rounded to cents when a Row is materialized, so rounding never
# feeds back into the next year's balance.
#
# Life events (a baby, an inheritance, a house down payment, Social
# Security) arrive as plain `events:` hashes; the projector never touches
# the records they were mapped from.
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

  # A normalized life event. The projector deliberately knows nothing about
  # where events come from (a caller maps its own records onto the `events:`
  # hashes), so this stays a pure math object.
  Event = Data.define(:start_age, :end_age, :one_time, :annual, :affects) do
    # Inclusive window. A nil end_age means the event lasts a single year,
    # so the window collapses to start_age.
    def covers?(age) = age >= start_age && age <= (end_age || start_age)

    # A one-time amount lands in the starting year only.
    def one_time_for(age) = age == start_age ? one_time : BigDecimal(0)
    def annual_for(age) = covers?(age) ? annual : BigDecimal(0)
    def amount_for(age) = annual_for(age) + one_time_for(age)
  end

  AFFECTS_INCOME = "income"
  AFFECTS_EXPENSES = "expenses"
  AFFECTS_PORTFOLIO = "portfolio"

  # tax_estimator is injected and only has to respond to
  # `estimate(gross_income:)` returning an object with a `#total`, which
  # keeps this class independent of any particular tax implementation.
  #
  # events is a list of anything responding to `[]` with the keys
  # :start_age, :end_age (nil allowed), :one_time, :annual and :affects
  # ("income" / "expenses" / "portfolio").
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
    horizon_age: 90,
    events: []
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

    @events = Array(events).filter_map { |event| build_event(event) }
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
        # expenses_for already folds in any expense-affecting events, so the
        # FIRE target rises for the years a recurring expense (kids, tuition)
        # is running and falls back once the window closes.
        expenses = expenses_for(offset)
        fire_number = fire_number_for(expenses)
        # Income events are quoted in today's dollars, so they inflate on the
        # same schedule as expenses.
        event_income = inflated_events_for(offset, AFFECTS_INCOME)
        retired = !fire_index.nil?

        if retired
          # Retirement rows carry no earned income in this model. An
          # income-affecting event in retirement (Social Security, a pension,
          # a rental) therefore shows up as a *smaller withdrawal* rather than
          # as income: the portfolio only has to cover expenses net of it.
          gross_income = BigDecimal(0)
          net_need = [ expenses - event_income, BigDecimal(0) ].max
          # The retirement tax rate is a gross-up on the withdrawal: the
          # portfolio has to fund the spending *and* the tax on it.
          withdrawal = net_need / (1 - (@retirement_tax_rate / 100))
          taxes = withdrawal - net_need
          savings = -withdrawal
        else
          # Event income is added to gross *before* taxes, so a raise, a
          # bonus, or a side business is taxed like the rest of the income.
          gross_income = income + event_income
          taxes = decimal(@tax_estimator.estimate(gross_income: gross_income).total)
          savings = gross_income - taxes - expenses
        end

        portfolio = (portfolio * (1 + (@expected_return / 100))) + savings
        # Portfolio events are direct transfers of investable assets (an
        # inheritance in, a house down payment out). They are applied after
        # the year's growth, are *not* inflation-adjusted (the user states a
        # dollar amount at a date, not a today's-dollars equivalent), and are
        # *not* taxed (the amount is what actually lands in the portfolio).
        portfolio += events_for(offset, AFFECTS_PORTFOLIO)
        # A portfolio cannot go below zero; once depleted it stays there
        # until positive savings rebuild it. A negative portfolio event
        # cannot push it below zero either.
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

    # Base spending inflates from today's dollars; expense events are quoted
    # in today's dollars too, so they inflate by the same factor.
    def expenses_for(offset)
      (@annual_expenses * inflation_factor(offset)) + inflated_events_for(offset, AFFECTS_EXPENSES)
    end

    def inflation_factor(offset)
      (1 + (@inflation / 100))**offset
    end

    # Total of every event of the given kind that applies in this year, in
    # today's dollars.
    def events_for(offset, affects)
      age = @current_age + offset
      @events.sum(BigDecimal(0)) { |event| event.affects == affects ? event.amount_for(age) : BigDecimal(0) }
    end

    def inflated_events_for(offset, affects)
      events_for(offset, affects) * inflation_factor(offset)
    end

    def build_event(event)
      start_age = event[:start_age]
      return nil if start_age.nil?

      end_age = event[:end_age]

      Event.new(
        start_age: start_age.to_i,
        end_age: end_age&.to_i,
        one_time: decimal_or_zero(event[:one_time]),
        annual: decimal_or_zero(event[:annual]),
        affects: event[:affects].to_s
      )
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

    # Event amounts are optional, so a missing one reads as no money.
    def decimal_or_zero(value)
      return BigDecimal(0) if value.nil? || value.to_s.strip.empty?

      decimal(value)
    end
end
