require "test_helper"

class DebtPayoffPlan::SimulatorTest < ActiveSupport::TestCase
  test "single debt at minimum only pays off in the hand-computed month with exact interest" do
    # 1000 at 12% APR (1%/mo), 100 minimum: amortizes in 11 months with
    # 58.98 of interest (verified by hand month-by-month).
    result = simulate([ debt(id: "a", balance: 1000, rate: 12, minimum: 100) ])

    assert_equal 11, result.months_to_payoff
    assert_equal BigDecimal("58.98"), result.total_interest
    assert_equal 11, result.debt_results.first.payoff_month
  end

  test "avalanche sends the extra payment to the highest rate debt first" do
    result = simulate(
      [
        debt(id: "low", balance: 1000, rate: 5, minimum: 50),
        debt(id: "high", balance: 1000, rate: 20, minimum: 50)
      ],
      strategy: "avalanche",
      extra_payment: 100
    )

    high = result.debt_results.find { |dr| dr.account_id == "high" }
    low = result.debt_results.find { |dr| dr.account_id == "low" }
    assert high.payoff_month < low.payoff_month
  end

  test "snowball sends the extra payment to the smallest balance first despite a lower rate" do
    result = simulate(
      [
        debt(id: "small", balance: 500, rate: 5, minimum: 25),
        debt(id: "big", balance: 2000, rate: 20, minimum: 50)
      ],
      strategy: "snowball",
      extra_payment: 100
    )

    small = result.debt_results.find { |dr| dr.account_id == "small" }
    big = result.debt_results.find { |dr| dr.account_id == "big" }
    assert small.payoff_month < big.payoff_month
  end

  test "a paid-off debt's minimum rolls into the pool and accelerates the rest" do
    # Zero rates keep the arithmetic exact: A's 100 minimum retires it in
    # month 1, then B pays 50 + the freed 100 per month.
    # B: 1200 - 50 (m1) = 1150, then 1150 / 150 = 7.67 → paid in month 9.
    result = simulate(
      [
        debt(id: "a", balance: 100, rate: 0, minimum: 100),
        debt(id: "b", balance: 1200, rate: 0, minimum: 50)
      ]
    )

    assert_equal 1, result.debt_results.find { |dr| dr.account_id == "a" }.payoff_month
    assert_equal 9, result.debt_results.find { |dr| dr.account_id == "b" }.payoff_month
  end

  test "a debt whose payment never outruns interest stops at the horizon instead of hanging" do
    result = simulate([ debt(id: "a", balance: 10_000, rate: 100, minimum: 10) ])

    assert_equal DebtPayoffPlan::Simulator::MAX_MONTHS, result.months_to_payoff
    assert_nil result.debt_results.first.payoff_month
  end

  test "interest on an exact half cent rounds up" do
    # 101 at 6% APR: 101 * 0.005 = 0.505 → 0.51 with half-up rounding.
    result = simulate([ debt(id: "a", balance: 101, rate: 6, minimum: 200) ])

    assert_equal BigDecimal("0.51"), result.total_interest
    assert_equal 1, result.months_to_payoff
  end

  test "balance history starts at the opening balance and ends at zero" do
    result = simulate([ debt(id: "a", balance: 1000, rate: 12, minimum: 100) ])
    balances = result.debt_results.first.balances

    assert_equal BigDecimal(1000), balances.first
    assert_equal BigDecimal(0), balances.last
    assert_equal result.months_to_payoff + 1, balances.size
  end

  private
    def simulate(debts, strategy: "avalanche", extra_payment: 0)
      DebtPayoffPlan::Simulator.new(debts, strategy: strategy, extra_payment: extra_payment).call
    end

    def debt(id:, balance:, rate:, minimum:)
      DebtPayoffPlan::DebtInput.new(
        account_id: id,
        name: id,
        accountable_type: "Loan",
        balance: BigDecimal(balance.to_s),
        annual_rate_percent: BigDecimal(rate.to_s),
        minimum_payment: BigDecimal(minimum.to_s),
        needs_info: false
      )
    end
end
