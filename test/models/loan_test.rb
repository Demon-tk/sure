require "test_helper"

class LoanTest < ActiveSupport::TestCase
  test "rejects invalid subtype" do
    loan = Loan.new(subtype: "invalid")

    assert_not loan.valid?
    assert_includes loan.errors[:subtype], "is not included in the list"
  end

  test "calculates correct monthly payment for fixed rate loan" do
    loan_account = Account.create! \
      family: families(:dylan_family),
      name: "Mortgage Loan",
      balance: 500000,
      currency: "USD",
      accountable: Loan.create!(
        subtype: "mortgage",
        interest_rate: 3.5,
        term_months: 360,
        rate_type: "fixed"
      )

    assert_equal 2245, loan_account.loan.monthly_payment.amount
  end

  test "payoff rate and minimum come from the fixed rate and amortized payment" do
    loan = accounts(:loan).loan

    assert_equal loan.interest_rate, loan.payoff_rate
    assert_equal loan.monthly_payment.amount, loan.payoff_minimum_payment
  end

  test "a stored minimum payment beats the amortized estimate" do
    loan = accounts(:loan).loan
    loan.update!(minimum_payment: 150)

    assert_equal 150, loan.payoff_minimum_payment
  end

  test "rate changes normalize, sort, and convert to month offsets" do
    loan = accounts(:loan).loan
    loan.update!(rate_changes: [
      { effective_on: 6.months.from_now.to_date.to_s, rate: "9.5" },
      { effective_on: 2.months.from_now.to_date.to_s, rate: "7" },
      { effective_on: "", rate: "3" }
    ])

    assert_equal 2, loan.rate_changes.size
    assert_equal [ "7.0", "9.5" ], loan.rate_changes.map { |e| e["rate"] }

    schedule = loan.payoff_rate_schedule
    assert_equal [ 2, 6 ], schedule.map(&:first)
    assert_equal BigDecimal("7"), schedule.first.last
  end

  test "a variable rate loan with a rate schedule still reports its payoff rate" do
    loan = accounts(:loan).loan
    loan.update!(rate_type: "variable", rate_changes: [ { effective_on: 1.year.from_now.to_date.to_s, rate: "8" } ])

    assert_equal loan.interest_rate, loan.payoff_rate
  end

  test "a variable rate loan reports no payoff rate" do
    loan = accounts(:loan).loan
    loan.update!(rate_type: "variable")

    assert_nil loan.payoff_rate
    assert_nil loan.payoff_minimum_payment
  end
end
