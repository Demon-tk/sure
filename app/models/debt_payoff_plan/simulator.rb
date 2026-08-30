# Month-by-month payoff simulation over a fixed set of debts. Pure math —
# no ActiveRecord, no currency conversion (inputs are already in one currency).
#
# Each month: interest accrues on every unpaid balance, minimums are paid,
# then the extra pool (the user's extra payment plus the freed minimums of
# already-paid-off debts) is applied in strategy order. The order is
# recomputed every month because the snowball ranking shifts as balances
# shrink. A debt with defer_months D (student-loan grace period) makes no
# payments and takes no extra money during months 1..D — interest still
# accrues — and behaves normally from month D+1 on.
class DebtPayoffPlan::Simulator
  # A debt that never amortizes (payment below accrued interest) would loop
  # forever; 30 years is far beyond any plannable horizon.
  MAX_MONTHS = 360

  PENNY = BigDecimal("0.01")

  Result = Data.define(:total_interest, :months_to_payoff, :payoff_date, :debt_results)

  # balances holds the end-of-month balance per month, index 0 = starting
  # balance, so the chart can draw the full trajectory. payoff_month is nil
  # when the debt is still unpaid at MAX_MONTHS.
  DebtResult = Data.define(:account_id, :payoff_month, :total_interest, :balances)

  def initialize(debts, strategy:, extra_payment: 0)
    @debts = debts
    @strategy = strategy
    @extra_payment = BigDecimal(extra_payment.to_s)
  end

  def call
    balances = debts.to_h { |d| [ d.account_id, BigDecimal(d.balance.to_s) ] }
    history = debts.to_h { |d| [ d.account_id, [ balances[d.account_id] ] ] }
    interest_paid = Hash.new(BigDecimal(0))
    payoff_months = {}
    freed_minimums = BigDecimal(0)
    months_elapsed = 0

    (1..MAX_MONTHS).each do |month|
      unpaid = debts.select { |d| balances[d.account_id] > PENNY }
      break if unpaid.empty?

      months_elapsed = month

      unpaid.each do |d|
        interest = (balances[d.account_id] * monthly_rate(d, month)).round(2, half: :up)
        balances[d.account_id] += interest
        interest_paid[d.account_id] += interest
      end

      # Deferred debts are absent from this month's payments entirely: no
      # minimum, no extra money, no place in the payment ordering.
      paying = unpaid.reject { |d| deferred?(d, month) }

      paying.each do |d|
        balances[d.account_id] -= [ minimum_for(d), balances[d.account_id] ].min
      end

      pool = extra_payment + freed_minimums
      ordered(paying, balances, month).each do |d|
        break if pool <= PENNY
        next if balances[d.account_id] <= PENNY

        applied = [ pool, balances[d.account_id] ].min
        balances[d.account_id] -= applied
        pool -= applied
      end

      unpaid.each do |d|
        next unless balances[d.account_id] <= PENNY && !payoff_months.key?(d.account_id)

        payoff_months[d.account_id] = month
        freed_minimums += minimum_for(d)
        balances[d.account_id] = BigDecimal(0)
      end

      debts.each { |d| history[d.account_id] << balances[d.account_id] }
    end

    Result.new(
      total_interest: interest_paid.values.sum(BigDecimal(0)),
      months_to_payoff: months_elapsed,
      payoff_date: Date.current + months_elapsed.months,
      debt_results: debts.map do |d|
        DebtResult.new(
          account_id: d.account_id,
          payoff_month: payoff_months[d.account_id],
          total_interest: interest_paid[d.account_id],
          balances: history[d.account_id]
        )
      end
    )
  end

  private
    attr_reader :debts, :strategy, :extra_payment

    # Walks the debt's rate schedule: the base rate applies until the first
    # change's month, each change applies from its month onward (a 0% intro
    # card jumping to its standard rate, an ARM resetting more than once).
    def monthly_rate(debt, month)
      rate = debt.annual_rate_percent
      debt.rate_schedule.each do |change_month, change_rate|
        rate = change_rate if month >= change_month
      end

      BigDecimal(rate.to_s) / 1200
    end

    def minimum_for(debt)
      BigDecimal(debt.minimum_payment.to_s)
    end

    # True during months 1..defer_months: the debt still accrues interest but
    # makes no payments and takes no extra money.
    def deferred?(debt, month)
      defer = debt.defer_months.to_i
      defer.positive? && month <= defer
    end

    def ordered(unpaid, balances, month)
      case strategy
      when "snowball"
        unpaid.sort_by { |d| balances[d.account_id] }
      else # avalanche — by the rate the debt charges *this* month, so a 0%
        # promo card stays last until its rate jumps
        unpaid.sort_by { |d| -monthly_rate(d, month) }
      end
    end
end
