require "test_helper"

class FirePlan::TaxEstimatorTest < ActiveSupport::TestCase
  test "hand-computed single filer at 100k with 5% state rate" do
    estimator = FirePlan::TaxEstimator.new(filing_status: "single", year: 2025, state_rate: 5.0)
    result = estimator.estimate(gross_income: 100_000)

    # taxable = 100,000 - 15,000 standard deduction = 85,000
    # federal = (11,925 * 0.10) + (36,550 * 0.12) + (36,525 * 0.22)
    #         = 1,192.50 + 4,386.00 + 8,035.50 = 13,614.00
    assert_equal BigDecimal("13614.00"), result.federal
    # fica = (100,000 * 0.062) + (100,000 * 0.0145) = 6,200.00 + 1,450.00 = 7,650.00
    assert_equal BigDecimal("7650.00"), result.fica
    assert_equal BigDecimal("5000.00"), result.state
    assert_equal BigDecimal("26264.00"), result.total
  end

  test "married filing jointly pays less federal tax than single at the same income" do
    single_federal = FirePlan::TaxEstimator.new(filing_status: "single").estimate(gross_income: 100_000).federal
    mfj_federal = FirePlan::TaxEstimator.new(filing_status: "married_filing_jointly").estimate(gross_income: 100_000).federal

    assert_operator mfj_federal, :<, single_federal
  end

  test "social security wage base caps the 6.2% portion of FICA" do
    estimator = FirePlan::TaxEstimator.new(filing_status: "single")
    result = estimator.estimate(gross_income: 300_000)

    # fica = (176,100 * 0.062) + (300,000 * 0.0145) + ((300,000 - 200,000) * 0.009)
    #      = 10,918.20 + 4,350.00 + 900.00 = 16,168.20
    assert_equal BigDecimal("16168.20"), result.fica
  end

  test "zero and negative gross income return an all-zero estimate" do
    estimator = FirePlan::TaxEstimator.new

    [ 0, -50_000 ].each do |gross|
      result = estimator.estimate(gross_income: gross)

      assert_equal BigDecimal("0"), result.total
      assert_equal BigDecimal("0"), result.effective_rate
    end
  end

  test "zero state rate produces zero state tax" do
    estimator = FirePlan::TaxEstimator.new(state_rate: 0)
    result = estimator.estimate(gross_income: 100_000)

    assert_equal BigDecimal("0"), result.state
  end

  test "unknown filing status falls back to single" do
    fallback = FirePlan::TaxEstimator.new(filing_status: "head_of_household").estimate(gross_income: 100_000)
    single = FirePlan::TaxEstimator.new(filing_status: "single").estimate(gross_income: 100_000)

    assert_equal single, fallback
  end
end
