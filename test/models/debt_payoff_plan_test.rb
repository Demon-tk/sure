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

  test "expected_return defaults to 7.0" do
    plan = build_plan

    assert_equal BigDecimal("7.0"), plan.expected_return
  end

  test "expected_return clamps to the 0..20 range" do
    plan = build_plan(expected_return: "50")

    assert_equal BigDecimal(20), plan.expected_return
  end

  test "advice_for recommends paying off a debt whose rate beats expected_return by more than 1%" do
    plan = build_plan(expected_return: "7")
    credit_card = find_debt(plan, :credit_card)

    advice = plan.advice_for(credit_card)

    assert_equal :payoff, advice.verdict
    assert_equal BigDecimal("18.99"), advice.comparison_rate
    assert_equal BigDecimal("119.90"), advice.annual_delta
  end

  test "advice_for recommends investing when expected_return beats the debt's rate by more than 1%" do
    plan = build_plan(expected_return: "7")
    loan = find_debt(plan, :loan)

    advice = plan.advice_for(loan)

    assert_equal :invest, advice.verdict
    assert advice.annual_delta.negative?
  end

  test "advice_for calls a tossup when the spread is within the 1% band" do
    plan = build_plan(expected_return: "3")
    loan = find_debt(plan, :loan)

    advice = plan.advice_for(loan)

    assert_equal :tossup, advice.verdict
  end

  test "advice_for judges a debt by its highest rate within the next 12 months, not a current promo rate" do
    accounts(:credit_card).credit_card.update!(
      apr: 0,
      rate_changes: [ { effective_on: 6.months.from_now.to_date.to_s, rate: "24" } ]
    )
    plan = build_plan(expected_return: "7")
    credit_card = find_debt(plan, :credit_card)

    advice = plan.advice_for(credit_card)

    assert_equal BigDecimal(24), advice.comparison_rate
    assert_equal :payoff, advice.verdict
  end

  test "advice_for returns nil for a debt that needs info" do
    plan = build_plan
    iou = find_debt(plan, :other_liability)

    assert_nil plan.advice_for(iou)
  end

  private
    def find_debt(plan, account_fixture)
      plan.debts.find { |d| d.account_id == accounts(account_fixture).id }
    end

    def build_plan(**options)
      DebtPayoffPlan.new(family: @family, user: @user, **options)
    end
end
