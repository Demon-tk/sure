require "test_helper"

class FirePlan::MonteCarloTest < ActiveSupport::TestCase
  PERCENTILE_KEYS = [ :p10, :p25, :p50, :p75, :p90 ]

  test "same seed produces identical results, different seed does not" do
    args = { portfolio: 500_000, cashflows: [ -20_000 ] * 20, mean_return: 6.0, volatility: 10.0 }

    result_a = FirePlan::MonteCarlo.new(trials: 500, seed: 42).simulate(**args)
    result_b = FirePlan::MonteCarlo.new(trials: 500, seed: 42).simulate(**args)
    result_c = FirePlan::MonteCarlo.new(trials: 500, seed: 7).simulate(**args)

    assert_equal result_a.success_rate, result_b.success_rate
    assert_equal result_a.percentiles, result_b.percentiles

    assert_not_equal result_a.percentiles, result_c.percentiles
  end

  test "zero volatility grows deterministically" do
    result = FirePlan::MonteCarlo.new(trials: 200, seed: 1).simulate(
      portfolio: 1000,
      cashflows: [ 0, 0 ],
      mean_return: 10.0,
      volatility: 0.0
    )

    final_year = result.percentiles.last
    assert_in_delta 1210, final_year[:p10], 1
    assert_in_delta 1210, final_year[:p90], 1
    assert_equal final_year[:p10], final_year[:p90]
  end

  test "guaranteed failure when withdrawals vastly exceed the portfolio" do
    result = FirePlan::MonteCarlo.new(trials: 200, seed: 1).simulate(
      portfolio: 100,
      cashflows: [ -1000 ] * 5,
      mean_return: 0.0,
      volatility: 0.0
    )

    assert_equal 0.0, result.success_rate
    result.percentiles[1..].each do |year|
      PERCENTILE_KEYS.each { |key| assert_equal 0, year[key] }
    end
  end

  test "guaranteed success when growth vastly exceeds withdrawals" do
    result = FirePlan::MonteCarlo.new(trials: 200, seed: 1).simulate(
      portfolio: 1_000_000,
      cashflows: [ -10_000 ] * 10,
      mean_return: 5.0,
      volatility: 1.0
    )

    assert_equal 100.0, result.success_rate
  end

  test "percentiles are ordered within a year" do
    result = FirePlan::MonteCarlo.new(trials: 1000, seed: 1).simulate(
      portfolio: 100_000,
      cashflows: [ 0 ] * 20,
      mean_return: 7.0,
      volatility: 15.0
    )

    final_year = result.percentiles.last
    assert_operator final_year[:p10], :<=, final_year[:p25]
    assert_operator final_year[:p25], :<=, final_year[:p50]
    assert_operator final_year[:p50], :<=, final_year[:p75]
    assert_operator final_year[:p75], :<=, final_year[:p90]
  end

  test "marginal plan produces a success rate strictly between 0 and 100" do
    result = FirePlan::MonteCarlo.new(trials: 1000, seed: 1).simulate(
      portfolio: 500_000,
      cashflows: [ -40_000 ] * 30,
      mean_return: 5.0,
      volatility: 12.0
    )

    assert_operator result.success_rate, :>, 0
    assert_operator result.success_rate, :<, 100
  end
end
