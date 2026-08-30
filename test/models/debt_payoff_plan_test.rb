require "test_helper"

class DebtPayoffPlanTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "enumerates the family's liability accounts" do
    plan = build_plan

    names = plan.debts.map(&:name)
    assert_includes names, accounts(:loan).name
    assert_includes names, accounts(:credit_card).name
    assert_includes names, accounts(:other_liability).name
  end

  test "a liability without rate or minimum needs info and is excluded from the simulation" do
    plan = build_plan
    iou = plan.debts.find { |d| d.account_id == accounts(:other_liability).id }

    assert iou.needs_info?
    assert_not_includes plan.payable_debts, iou
    assert plan.needs_info?
  end

  test "overrides supply the missing rate and minimum and make the debt payable" do
    plan = build_plan(
      overrides: { accounts(:other_liability).id => { rate: "10", minimum_payment: "50" } }
    )
    iou = plan.debts.find { |d| d.account_id == accounts(:other_liability).id }

    assert_not iou.needs_info?
    assert_includes plan.payable_debts, iou
    assert_equal BigDecimal(10), iou.annual_rate_percent
  end

  test "an unknown strategy falls back to avalanche and a negative extra payment clamps to zero" do
    plan = build_plan(strategy: "yolo", extra_payment: "-50")

    assert_equal "avalanche", plan.strategy
    assert_equal 0, plan.extra_payment
  end

  test "an extra payment saves interest against the minimum-only baseline" do
    plan = build_plan(extra_payment: "500")

    assert plan.interest_saved.positive?
    assert plan.months_to_payoff < build_plan.months_to_payoff
  end

  test "chart payload has one series per payable debt with pre-formatted points" do
    plan = build_plan
    payload = plan.chart_payload

    assert_equal plan.payable_debts.size, payload[:series].size
    first_point = payload[:series].first[:points].first
    assert first_point[:value_formatted].present?
    assert first_point[:date_formatted].present?
  end

  private
    def build_plan(**options)
      DebtPayoffPlan.new(family: @family, user: @user, **options)
    end
end
