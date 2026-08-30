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

  test "a promo rate accrues nothing until it expires, then the scheduled rate kicks in" do
    # 1200 at 0% for 6 months then 12% APR, 100 minimum. Months 1-6 are
    # interest-free (balance 600 after month 6); the remaining balance
    # amortizes at 1%/mo — hand-computed: paid off in month 13, 21.93 interest.
    result = simulate(
      [ debt(id: "promo", balance: 1200, rate: 0, minimum: 100, rate_schedule: [ [ 7, BigDecimal(12) ] ]) ]
    )

    assert_equal 13, result.months_to_payoff
    assert_equal BigDecimal("21.93"), result.total_interest
  end

  test "multiple scheduled rate changes each take over in their month" do
    # 1000 at 0%, stepping to 12% in month 3 and 24% in month 6, 100 minimum.
    # Hand-computed month by month: paid off in month 11, 56.17 interest.
    result = simulate(
      [ debt(id: "arm", balance: 1000, rate: 0, minimum: 100, rate_schedule: [ [ 3, BigDecimal(12) ], [ 6, BigDecimal(24) ] ]) ]
    )

    assert_equal 11, result.months_to_payoff
    assert_equal BigDecimal("56.17"), result.total_interest
  end

  test "avalanche deprioritizes a promo card until its rate jumps" do
    # Promo card at 0% (jumping to 30% in month 13) vs a 10% loan. While
    # the promo runs, the extra payment goes to the loan.
    result = simulate(
      [
        debt(id: "promo", balance: 5000, rate: 0, minimum: 50, rate_schedule: [ [ 13, BigDecimal(30) ] ]),
        debt(id: "loan", balance: 5000, rate: 10, minimum: 50)
      ],
      extra_payment: 400
    )

    loan = result.debt_results.find { |dr| dr.account_id == "loan" }
    promo = result.debt_results.find { |dr| dr.account_id == "promo" }
    assert loan.payoff_month < promo.payoff_month
  end

  test "balance history starts at the opening balance and ends at zero" do
    result = simulate([ debt(id: "a", balance: 1000, rate: 12, minimum: 100) ])
    balances = result.debt_results.first.balances

    assert_equal BigDecimal(1000), balances.first
    assert_equal BigDecimal(0), balances.last
    assert_equal result.months_to_payoff + 1, balances.size
  end

  test "a deferred debt accrues interest but makes no payment during its deferment" do
    # 1000 at 12% APR (1%/mo), 100 minimum, 2-month deferment. Months 1-2
    # grow the balance by 1% with no payment: 1010, then 1020.10.
    result = simulate([ debt(id: "a", balance: 1000, rate: 12, minimum: 100, defer_months: 2) ])
    balances = result.debt_results.first.balances

    assert_equal BigDecimal("1000"), balances[0]
    assert_equal BigDecimal("1010"), balances[1]
    assert_equal BigDecimal("1020.10"), balances[2]
  end

  test "a deferred debt resumes minimum payments at month D+1" do
    # 1000 at 12% APR, 100 minimum, 2-month deferment. Month 3: interest
    # (1020.10 * 1% = 10.20) then the 100 minimum resumes: 930.30.
    result = simulate([ debt(id: "a", balance: 1000, rate: 12, minimum: 100, defer_months: 2) ])
    balances = result.debt_results.first.balances

    assert_equal BigDecimal("1020.10"), balances[2]
    assert_equal BigDecimal("930.30"), balances[3]
  end

  test "other debts still receive the extra payment while one debt is deferred" do
    # "deferred" (12% APR, 2-month deferment) takes no money in months 1-2,
    # so the 100 extra payment flows entirely to the 0% debt each month:
    # 1000 - 50 min - 100 extra = 850, then 700.
    result = simulate(
      [
        debt(id: "deferred", balance: 1000, rate: 12, minimum: 100, defer_months: 2),
        debt(id: "other", balance: 1000, rate: 0, minimum: 50)
      ],
      extra_payment: 100
    )

    other = result.debt_results.find { |dr| dr.account_id == "other" }
    deferred = result.debt_results.find { |dr| dr.account_id == "deferred" }

    assert_equal BigDecimal("850"), other.balances[1]
    assert_equal BigDecimal("700"), other.balances[2]
    assert_equal BigDecimal("1010"), deferred.balances[1]
    assert_equal BigDecimal("1020.10"), deferred.balances[2]
  end

  private
    def simulate(debts, strategy: "avalanche", extra_payment: 0)
      DebtPayoffPlan::Simulator.new(debts, strategy: strategy, extra_payment: extra_payment).call
    end

    def debt(id:, balance:, rate:, minimum:, rate_schedule: [], defer_months: 0)
      DebtPayoffPlan::DebtInput.new(
        account_id: id,
        name: id,
        accountable_type: "Loan",
        balance: BigDecimal(balance.to_s),
        annual_rate_percent: BigDecimal(rate.to_s),
        minimum_payment: BigDecimal(minimum.to_s),
        rate_schedule: rate_schedule,
        needs_info: false,
        defer_months: defer_months
      )
    end
end
