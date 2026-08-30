# Randomized portfolio outcome simulation for a FIRE plan. Runs many
# independent trials of "apply a random annual return, then apply this
# year's net cashflow" and reports how many trials never ran the portfolio
# to zero, plus percentile bands of portfolio value per year.
#
# This is statistical simulation, not ledger accounting, so plain Floats
# (not BigDecimal) are used throughout for speed and simplicity — the
# output is inherently an approximation, and Float error is invisible next
# to the noise of the simulation itself.
class FirePlan::MonteCarlo
  MIN_TRIALS = 100
  MAX_TRIALS = 10_000
  PERCENTILES = [ 10, 25, 50, 75, 90 ].freeze

  Result = Data.define(:success_rate, :percentiles, :trials)

  def initialize(trials: 1000, seed: 42)
    @trials = trials.clamp(MIN_TRIALS, MAX_TRIALS)
    @random = Random.new(seed)
  end

  # cashflows: array of yearly net flows, one entry per simulated year
  # (positive = contribution, negative = withdrawal). mean_return and
  # volatility are percents (e.g. 7.0, 15.0), representing the mean and
  # standard deviation of the assumed annual return distribution.
  def simulate(portfolio:, cashflows:, mean_return:, volatility:)
    return Result.new(success_rate: 100.0, percentiles: [], trials: @trials) if cashflows.empty?

    mean = mean_return / 100.0
    stddev = volatility / 100.0
    years = cashflows.length

    # balances_by_year[y] holds the ending balance for every trial after year y
    balances_by_year = Array.new(years) { Array.new(@trials) }
    failures = 0

    @trials.times do |trial|
      balance = portfolio.to_f
      failed = false

      years.times do |y|
        unless failed
          r = mean + (stddev * gaussian)
          balance = (balance * (1 + r)) + cashflows[y]

          if balance <= 0
            balance = 0.0
            failed = true
          end
        end

        balances_by_year[y][trial] = balance
      end

      failures += 1 if failed
    end

    percentiles = balances_by_year.each_with_index.map do |values, year_index|
      percentiles_for(values).merge(year_index: year_index)
    end

    success_rate = (((@trials - failures) / @trials.to_f) * 100).round(1)

    Result.new(success_rate: success_rate, percentiles: percentiles, trials: @trials)
  end

  private

    # Box-Muller transform: turns two uniform random draws into one
    # standard-normal (mean 0, stddev 1) draw, using this instance's single
    # seeded Random so a given seed always produces the same sequence.
    def gaussian
      u1 = 1.0 - @random.rand # avoid log(0)
      u2 = @random.rand
      Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    end

    def percentiles_for(values)
      sorted = values.sort
      count = sorted.length

      PERCENTILES.each_with_object({}) do |pct, hash|
        # Nearest-rank by linear interpolation position: index scales pct
        # across the sorted array and rounds to the closest sample rather
        # than interpolating between two — simple and stable for the
        # trial counts this class supports (100-10,000).
        index = ((count - 1) * pct / 100.0).round
        hash[:"p#{pct}"] = sorted[index].round
      end
    end
end
