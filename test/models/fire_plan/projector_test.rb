require "test_helper"
require "ostruct"

class FirePlan::ProjectorTest < ActiveSupport::TestCase
  # Stands in for FirePlan::TaxEstimator so these tests only exercise the
  # projection math: a flat percentage of gross income, no brackets.
  FakeTax = Struct.new(:rate) do
    def estimate(gross_income:)
      OpenStruct.new(total: BigDecimal(gross_income.to_s) * BigDecimal(rate.to_s))
    end
  end

  # Every scenario below uses zero inflation and zero income growth unless it
  # is specifically testing those, so the expected numbers are hand-checkable.
  def project(overrides = {})
    defaults = {
      tax_estimator: FakeTax.new("0"),
      current_age: 30,
      portfolio: 0,
      gross_income: 0,
      annual_expenses: 0,
      income_growth: 0,
      inflation: 0,
      expected_return: 0,
      swr: 4,
      retirement_tax_rate: 0,
      horizon_age: 90
    }

    FirePlan::Projector.new(**defaults.merge(overrides)).project
  end

  test "accumulates savings until the portfolio covers the target" do
    projection = project(
      tax_estimator: FakeTax.new("0.20"),
      portfolio: 0,
      gross_income: 100_000,
      annual_expenses: 50_000
    )

    first = projection.rows.first
    assert_equal BigDecimal(1_250_000), first.fire_number
    assert_equal BigDecimal(20_000), first.taxes
    assert_equal BigDecimal(30_000), first.savings
    assert_equal BigDecimal(30_000), first.portfolio

    # 30,000 saved per year first clears 1,250,000 in year 42 (1,260,000),
    # which is row index 41.
    assert_equal BigDecimal(1_260_000), projection.rows[41].portfolio
    assert projection.rows[41].fired?
    assert_not projection.rows[40].fired?

    assert_equal 71, projection.fire_age
    assert_equal 42, projection.years_to_fire
    assert_equal Date.current.year + 41, projection.fire_year
    assert_equal BigDecimal(1_250_000), projection.fire_number
    assert projection.fired_within_horizon?
    assert_equal 61, projection.rows.length
  end

  test "an already funded portfolio fires immediately and then draws down" do
    projection = project(portfolio: 2_000_000, annual_expenses: 50_000)

    # Year one is still an accumulation year (no income, so it spends
    # 50,000 out of the portfolio) but it ends above the 1,250,000 target.
    assert projection.rows.first.fired?
    assert_equal BigDecimal(1_950_000), projection.rows.first.portfolio
    assert_equal 1, projection.years_to_fire
    assert_equal 30, projection.fire_age

    # Every retirement year withdraws exactly the (untaxed) expenses.
    projection.rows.first(20).each_cons(2) do |previous, current|
      assert_equal previous.portfolio - BigDecimal(50_000), current.portfolio
    end
    assert_equal BigDecimal(2_000_000) - (BigDecimal(50_000) * 6), projection.rows[5].portfolio
  end

  test "retirement withdrawals are grossed up for the retirement tax rate" do
    projection = project(
      portfolio: 2_000_000,
      annual_expenses: 40_000,
      retirement_tax_rate: 20
    )

    retirement_row = projection.rows[1]
    assert_equal BigDecimal(0), retirement_row.gross_income
    assert_equal BigDecimal(40_000), retirement_row.expenses
    # 40,000 of spending needs a 50,000 withdrawal at a 20% rate.
    assert_equal BigDecimal(10_000), retirement_row.taxes
    assert_equal BigDecimal(-50_000), retirement_row.savings
    assert_equal BigDecimal(1_960_000) - BigDecimal(50_000), retirement_row.portfolio
  end

  test "a depleted portfolio floors at zero and never goes negative" do
    projection = project(portfolio: 10_000, gross_income: 0, annual_expenses: 100_000)

    assert_equal BigDecimal(0), projection.rows.first.portfolio
    assert_equal BigDecimal(0), projection.rows.last.portfolio
    assert projection.rows.none? { |row| row.portfolio.negative? }
    assert_not projection.fired_within_horizon?
  end

  test "never fires when there is nothing left to save" do
    projection = project(gross_income: 60_000, annual_expenses: 60_000)

    assert projection.rows.all? { |row| row.savings.zero? }
    assert_not projection.fired_within_horizon?
    assert_nil projection.fire_age
    assert_nil projection.fire_year
    assert_nil projection.years_to_fire
    assert_equal BigDecimal(1_500_000), projection.fire_number
    assert projection.rows.none?(&:fired?)
    assert_equal 90, projection.rows.last.age
  end

  test "inflation raises the target every year" do
    projection = project(annual_expenses: 50_000, inflation: 3)

    assert_equal BigDecimal(1_250_000), projection.rows.first.fire_number
    assert projection.rows[10].fire_number > projection.rows.first.fire_number
    assert projection.rows[10].expenses > projection.rows.first.expenses
  end

  # --- life events -------------------------------------------------------

  test "a recurring expense event only raises spending inside its window" do
    projection = project(
      gross_income: 100_000,
      annual_expenses: 50_000,
      events: [ { start_age: 32, end_age: 33, annual: 12_000, one_time: 0, affects: "expenses" } ]
    )

    by_age = projection.rows.index_by(&:age)

    assert_equal BigDecimal(50_000), by_age[31].expenses
    assert_equal BigDecimal(62_000), by_age[32].expenses
    assert_equal BigDecimal(62_000), by_age[33].expenses
    assert_equal BigDecimal(50_000), by_age[34].expenses

    # Untaxed here, so savings absorb the whole difference.
    assert_equal BigDecimal(50_000), by_age[31].savings
    assert_equal BigDecimal(38_000), by_age[32].savings
    assert_equal BigDecimal(38_000), by_age[33].savings
    assert_equal BigDecimal(50_000), by_age[34].savings

    # The target follows the spending it has to fund.
    assert_equal BigDecimal(1_550_000), by_age[32].fire_number
    assert_equal BigDecimal(1_250_000), by_age[34].fire_number
  end

  test "a one-time portfolio event lands in that year's ending balance" do
    inputs = { portfolio: 100_000, gross_income: 60_000, annual_expenses: 50_000 }
    without = project(inputs)
    with = project(inputs.merge(
      events: [ { start_age: 40, end_age: nil, one_time: 50_000, annual: 0, affects: "portfolio" } ]
    ))

    by_age_without = without.rows.index_by(&:age)
    by_age_with = with.rows.index_by(&:age)

    assert_equal by_age_without[39].portfolio, by_age_with[39].portfolio
    assert_equal by_age_without[40].portfolio + BigDecimal(50_000), by_age_with[40].portfolio
    # It stays in the balance for every later year too.
    assert_equal by_age_without[41].portfolio + BigDecimal(50_000), by_age_with[41].portfolio
    # A pure transfer: it is not treated as taxable income.
    assert_equal by_age_without[40].taxes, by_age_with[40].taxes
    assert_equal by_age_without[40].savings, by_age_with[40].savings
  end

  test "a negative portfolio event cannot push the portfolio below zero" do
    projection = project(
      portfolio: 100_000,
      gross_income: 60_000,
      annual_expenses: 50_000,
      events: [ { start_age: 30, end_age: nil, one_time: -500_000, annual: 0, affects: "portfolio" } ]
    )

    assert_equal BigDecimal(0), projection.rows.first.portfolio
    assert projection.rows.none? { |row| row.portfolio.negative? }
  end

  test "an income event is taxed like the rest of the income" do
    projection = project(
      tax_estimator: FakeTax.new("0.20"),
      gross_income: 100_000,
      annual_expenses: 50_000,
      events: [ { start_age: 35, end_age: nil, annual: 10_000, one_time: 0, affects: "income" } ]
    )

    by_age = projection.rows.index_by(&:age)

    assert_equal BigDecimal(100_000), by_age[34].gross_income
    assert_equal BigDecimal(20_000), by_age[34].taxes
    assert_equal BigDecimal(30_000), by_age[34].savings

    assert_equal BigDecimal(110_000), by_age[35].gross_income
    assert_equal BigDecimal(22_000), by_age[35].taxes
    assert_equal BigDecimal(38_000), by_age[35].savings

    # A nil end_age is a single year, so the raise does not persist.
    assert_equal BigDecimal(100_000), by_age[36].gross_income
  end

  test "a recurring expense event pushes FIRE out" do
    inputs = { tax_estimator: FakeTax.new("0.20"), gross_income: 100_000, annual_expenses: 50_000 }
    without = project(inputs)
    with = project(inputs.merge(
      events: [ { start_age: 32, end_age: 41, annual: 12_000, one_time: 0, affects: "expenses" } ]
    ))

    assert_equal 71, without.fire_age
    # Ten years of 12,000 less saved costs four extra working years.
    assert_equal 75, with.fire_age
    assert with.fire_age > without.fire_age
    assert with.years_to_fire > without.years_to_fire
  end

  test "an income event in retirement shrinks the withdrawal instead of the income row" do
    projection = project(
      portfolio: 5_000_000,
      annual_expenses: 50_000,
      retirement_tax_rate: 0,
      events: [ { start_age: 30, end_age: 90, annual: 20_000, one_time: 0, affects: "income" } ]
    )

    retirement_rows = projection.rows[1..5]

    retirement_rows.each do |row|
      assert row.fired?
      # The retired row reports the event income (20,000) as gross income even
      # though the withdrawal math nets it off spending.
      assert_equal BigDecimal(20_000), row.gross_income
      assert_equal BigDecimal(50_000), row.expenses
      # 50,000 of spending less 20,000 of Social-Security-style income.
      assert_equal BigDecimal(-30_000), row.savings
    end
  end

  test "retirement income beyond expenses floors the withdrawal at zero" do
    projection = project(
      portfolio: 5_000_000,
      annual_expenses: 50_000,
      retirement_tax_rate: 20,
      events: [ { start_age: 30, end_age: 90, annual: 80_000, one_time: 0, affects: "income" } ]
    )

    row = projection.rows[3]
    assert row.fired?
    assert_equal BigDecimal(0), row.savings
    assert_equal BigDecimal(0), row.taxes
  end
end
