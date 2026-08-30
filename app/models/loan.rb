class Loan < ApplicationRecord
  include Accountable
  include RateChangeable

  SUBTYPES = {
    "mortgage" => { short: "Mortgage", long: "Mortgage" },
    "student" => { short: "Student Loan", long: "Student Loan" },
    "auto" => { short: "Auto Loan", long: "Auto Loan" },
    "home_equity" => { short: "Home Equity", long: "Home Equity Loan" },
    "line_of_credit" => { short: "Line of Credit", long: "Line of Credit" },
    "business" => { short: "Business Loan", long: "Business Loan" },
    "other" => { short: "Other Loan", long: "Other Loan" }
  }.freeze

  validates :subtype, inclusion: { in: SUBTYPES.keys }, allow_blank: true

  def monthly_payment
    return nil if term_months.nil? || interest_rate.nil? || rate_type.nil? || rate_type != "fixed"
    return Money.new(0, account.currency) if account.loan.original_balance.amount.zero? || term_months.zero?

    annual_rate = interest_rate / 100.0
    monthly_rate = annual_rate / 12.0

    if monthly_rate.zero?
      payment = account.loan.original_balance.amount / term_months
    else
      payment = (account.loan.original_balance.amount * monthly_rate * (1 + monthly_rate)**term_months) / ((1 + monthly_rate)**term_months - 1)
    end

    Money.new(payment.round, account.currency)
  end

  def original_balance
    Money.new(account.first_valuation_amount, account.currency)
  end

  def minimum_payment_money
    minimum_payment ? Money.new(minimum_payment, account.currency) : nil
  end

  # Variable-rate loans have no dependable rate, so they report nil and
  # DebtPayoffPlan asks the user — unless a rate-change schedule is stored,
  # in which case the current interest_rate plus the schedule is the model.
  def payoff_rate
    interest_rate if rate_type == "fixed" || rate_changes.present?
  end

  # The servicer's actual minimum wins when stored; the amortized payment is
  # only an estimate (income-driven plans and escrow make them differ).
  def payoff_minimum_payment
    minimum_payment.presence || monthly_payment&.amount
  end

  class << self
    def color
      "#D444F1"
    end

    def icon
      "hand-coins"
    end

    def classification
      "liability"
    end
  end
end
