require "test_helper"

class FirePlanTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "assumptions default, clamp, and fall back on invalid filing status" do
    plan = FirePlan.new(family: @family, assumptions: { swr: "900", current_age: "-5", filing_status: "yolo" })

    assert_equal BigDecimal(10), plan.assumption(:swr)
    assert_equal BigDecimal(16), plan.assumption(:current_age)
    assert_equal BigDecimal("3.0"), plan.assumption(:inflation)
    assert_equal "single", plan.filing_status
  end

  test "explicit overrides beat derived family data" do
    plan = FirePlan.new(family: @family, assumptions: {
      gross_income: "120000", annual_expenses: "48000", portfolio: "250000"
    })

    assert_equal BigDecimal(120_000), plan.gross_income
    assert_equal BigDecimal(48_000), plan.annual_expenses
    assert_equal BigDecimal(250_000), plan.portfolio
  end

  test "derived inputs come from the income statement and investable balances" do
    plan = FirePlan.new(family: @family)

    # dylan_family fixtures include an Investment account (10,000) and a
    # Crypto account; the exact sum matters less than the wiring.
    assert plan.portfolio >= 10_000
    assert_kind_of BigDecimal, plan.gross_income
    assert_kind_of BigDecimal, plan.annual_expenses
  end

  test "projection and monte carlo run end to end on overridden inputs" do
    plan = FirePlan.new(family: @family, assumptions: {
      gross_income: "150000", annual_expenses: "50000", portfolio: "300000", current_age: "35"
    })

    assert plan.projection.rows.any?
    assert plan.fire_number.positive?
    assert_includes 0.0..100.0, plan.monte_carlo.success_rate
    assert_equal plan.projection.rows.size, plan.monte_carlo.percentiles.size
  end

  test "chart payload pairs deterministic rows with percentile bands" do
    plan = FirePlan.new(family: @family, assumptions: {
      gross_income: "150000", annual_expenses: "50000", portfolio: "300000", current_age: "35"
    })
    payload = plan.chart_payload

    assert_equal plan.projection.rows.size, payload[:rows].size
    first = payload[:rows].first
    assert first[:value_formatted].present?
    assert first.key?(:p10)
    assert payload[:fire_number_label].present?
  end
end
