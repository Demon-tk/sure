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

  test "milestones move the projection away from its baseline" do
    milestones = @family.fire_milestones.active
    assert milestones.any?, "expected active fire_milestones fixtures for dylan_family"

    # Start the plan at the earliest milestone so every fixture window falls
    # inside the projected horizon.
    start_age = [ milestones.minimum(:start_age).to_i, 16 ].max
    plan = FirePlan.new(family: @family, assumptions: {
      gross_income: "150000", annual_expenses: "50000", portfolio: "300000", current_age: start_age.to_s
    })

    assert_equal plan.milestones.size, milestones.count
    assert_equal plan.projection.rows.size, plan.baseline_projection.rows.size
    assert_not_equal plan.baseline_projection.rows.map(&:portfolio), plan.projection.rows.map(&:portfolio)

    delta = plan.fire_age_delta
    assert delta.nil? || delta.is_a?(Integer), "fire_age_delta must be an Integer or nil"

    payload = plan.chart_payload
    assert_equal plan.projection.rows.size, payload[:baseline].size
    assert_equal plan.projection.rows.first.year, payload[:baseline].first[:year]
    assert_kind_of Float, payload[:baseline].first[:value]
    assert_equal plan.baseline_projection.rows.first.portfolio.to_f, payload[:baseline].first[:value]
    assert_equal delta, payload[:fire_age_delta]
  end

  test "a family without milestones gets no baseline series to compare against" do
    plan = FirePlan.new(family: families(:empty), assumptions: {
      gross_income: "150000", annual_expenses: "50000", portfolio: "300000", current_age: "35"
    })

    assert_empty plan.milestones
    assert_nil plan.chart_payload[:baseline]
    # Identical projections, so there is no gap (or no FIRE date at all).
    assert_includes [ 0, nil ], plan.fire_age_delta
    assert_equal plan.baseline_projection.rows.map(&:portfolio), plan.projection.rows.map(&:portfolio)
  end
end
