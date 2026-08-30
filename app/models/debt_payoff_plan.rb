# A family's debt payoff plan: enumerates visible liability accounts,
# simulates avalanche/snowball payoff with an optional extra monthly payment,
# and compares against a minimum-payments-only baseline. Not persisted —
# strategy and extra payment travel as query params.
class DebtPayoffPlan
  include Monetizable

  monetize :total_debt, :total_interest, :interest_saved

  STRATEGIES = %w[avalanche snowball].freeze

  # rate_schedule holds scheduled APR changes as [[month_offset, rate]] from
  # the accountable's stored rate_changes (promo expirations, ARM resets).
  # Empty = flat annual_rate_percent for the whole simulation. defer_months
  # is the student-loan grace period: no payments for the first D months
  # (0 = no deferment).
  DebtInput = Data.define(:account_id, :name, :accountable_type, :balance, :annual_rate_percent, :minimum_payment, :rate_schedule, :needs_info, :defer_months) do
    def needs_info? = needs_info
  end

  # comparison_rate is the APR the debt is judged against (see #advice_for);
  # annual_delta is positive when paying the debt off beats investing.
  Advice = Data.define(:verdict, :comparison_rate, :annual_delta)

  # Matches FirePlan's default expected_return assumption.
  DEFAULT_EXPECTED_RETURN = BigDecimal("7.0")

  attr_reader :family, :strategy, :extra_payment, :overrides, :expected_return

  def initialize(family:, user: nil, strategy: nil, extra_payment: nil, overrides: {}, expected_return: nil)
    @family = family
    @user = user
    @strategy = STRATEGIES.include?(strategy) ? strategy : "avalanche"
    @extra_payment = [ BigDecimal(extra_payment.presence || 0, 12), BigDecimal(0) ].max
    @overrides = overrides || {}
    @expected_return = BigDecimal(expected_return.presence || DEFAULT_EXPECTED_RETURN, 12).clamp(BigDecimal(0), BigDecimal(20))
  end

  def debts
    @debts ||= liability_rows.map { |row| build_debt_input(row) }
  end

  def payable_debts
    debts.reject(&:needs_info?)
  end

  def needs_info?
    debts.any?(&:needs_info?)
  end

  def any_debts? = debts.any?

  def result
    @result ||= simulate(extra_payment)
  end

  def baseline_result
    @baseline_result ||= simulate(0)
  end

  def total_debt
    debts.sum(BigDecimal(0), &:balance)
  end

  def total_interest = result.total_interest

  def interest_saved
    [ baseline_result.total_interest - result.total_interest, BigDecimal(0) ].max
  end

  def months_to_payoff = result.months_to_payoff
  def payoff_date = result.payoff_date

  # Some debt's payment never outruns its interest, so the simulation stopped
  # at the horizon instead of reaching zero.
  def capped?
    payable_debts.any? && result.debt_results.any? { |dr| dr.payoff_month.nil? }
  end

  def debt_result_for(debt)
    result.debt_results.find { |dr| dr.account_id == debt.account_id }
  end

  # Invest-vs-payoff verdict for one debt: is expected_return likely to beat
  # what this debt costs, or vice versa?
  def advice_for(debt)
    return nil if debt.needs_info?

    # Judge the debt by the highest APR it will charge within the next 12
    # months, not today's rate — a 0% promo card that jumps to 24% in month
    # 3 must be judged by the 24%, not the teaser.
    near_term_rates = debt.rate_schedule.select { |month_offset, _rate| month_offset <= 12 }.map(&:last)
    comparison_rate = [ debt.annual_rate_percent, *near_term_rates ].max
    spread = comparison_rate - expected_return

    # +/-1% band: both comparison_rate and expected_return are estimates, so
    # a wafer-thin edge isn't worth a confident verdict either way.
    verdict =
      if spread > 1
        :payoff
      elsif spread < -1
        :invest
      else
        :tossup
      end

    Advice.new(
      verdict: verdict,
      comparison_rate: comparison_rate,
      annual_delta: (debt.balance * spread / 100).round(2)
    )
  end

  # Both strategies' outcomes side by side. With no extra payment or fewer
  # than three competing debts the schedules are often identical — showing
  # both numbers is what makes that legible instead of looking broken.
  def comparison
    @comparison ||= STRATEGIES.index_with do |s|
      s == strategy ? result : Simulator.new(payable_debts, strategy: s, extra_payment: extra_payment).call
    end
  end

  def strategies_identical?
    comparison["avalanche"].total_interest == comparison["snowball"].total_interest &&
      comparison["avalanche"].months_to_payoff == comparison["snowball"].months_to_payoff
  end

  def currency
    family.currency
  end

  # Everything the chart draws, pre-formatted server-side. One series per
  # payable debt, each declining to zero at its payoff month. Colors come
  # from a fixed palette by index: the accountable-type color is per class,
  # so two loans would collide.
  CHART_COLORS = %w[#3B82F6 #F13636 #D444F1 #F59E0B #10B981 #6366F1 #EC4899 #14B8A6].freeze

  def chart_payload
    {
      currency_symbol: Money::Currency.new(currency).symbol,
      months_to_payoff: months_to_payoff,
      payoff_date_label: I18n.l(payoff_date, format: :long),
      series: payable_debts.map.with_index do |debt, i|
        debt_result = debt_result_for(debt)
        {
          account_id: debt.account_id,
          name: debt.name,
          color: CHART_COLORS[i % CHART_COLORS.size],
          payoff_month: debt_result.payoff_month,
          points: debt_result.balances.map.with_index do |balance, month|
            {
              month: month,
              date: (Date.current + month.months).iso8601,
              date_formatted: I18n.l(Date.current + month.months, format: :long),
              value: balance.to_f,
              value_formatted: Money.new(balance, currency).format
            }
          end
        }
      end
    }
  end

  private
    attr_reader :user

    def liability_rows
      BalanceSheet.new(family, user: user)
        .liabilities
        .account_groups
        .flat_map(&:accounts)
        .select { |row| row.included_in_finances? && !row.exclude_from_reports? }
    end

    def build_debt_input(row)
      override = overrides[row.account.id] || {}
      rate = override[:rate].presence || row.accountable.payoff_rate
      minimum = override[:minimum_payment].presence || row.accountable.payoff_minimum_payment
      defer = override[:defer].presence.to_i.clamp(0, 120)

      DebtInput.new(
        account_id: row.account.id,
        name: row.name,
        accountable_type: row.accountable_type,
        balance: row.converted_balance,
        annual_rate_percent: rate&.to_d,
        minimum_payment: minimum&.to_d,
        rate_schedule: row.accountable.payoff_rate_schedule,
        needs_info: rate.blank? || minimum.blank?,
        defer_months: defer
      )
    end

    def simulate(extra)
      Simulator.new(payable_debts, strategy: strategy, extra_payment: extra).call
    end
end
