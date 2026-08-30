# Planning-grade estimate of US federal income tax, FICA, and state tax
# liability for a given gross income. Targets roughly 80% accuracy for FIRE
# projection purposes and is NOT a substitute for tax preparation or advice.
#
# Bracket and deduction tables below are keyed by year so they can be
# refreshed annually without touching the calculation logic.
class FirePlan::TaxEstimator
  VALID_FILING_STATUSES = [ "single", "married_filing_jointly" ].freeze

  STANDARD_DEDUCTION = {
    2025 => {
      "single" => BigDecimal("15000"),
      "married_filing_jointly" => BigDecimal("30000")
    }
  }.freeze

  # Each entry is [ lower_bound, rate ], sorted ascending, applied to taxable
  # income (gross minus standard deduction, floored at 0).
  FEDERAL_BRACKETS = {
    2025 => {
      "single" => [
        [ BigDecimal("0"), BigDecimal("0.10") ],
        [ BigDecimal("11925"), BigDecimal("0.12") ],
        [ BigDecimal("48475"), BigDecimal("0.22") ],
        [ BigDecimal("103350"), BigDecimal("0.24") ],
        [ BigDecimal("197300"), BigDecimal("0.32") ],
        [ BigDecimal("250525"), BigDecimal("0.35") ],
        [ BigDecimal("626350"), BigDecimal("0.37") ]
      ],
      "married_filing_jointly" => [
        [ BigDecimal("0"), BigDecimal("0.10") ],
        [ BigDecimal("23850"), BigDecimal("0.12") ],
        [ BigDecimal("96950"), BigDecimal("0.22") ],
        [ BigDecimal("206700"), BigDecimal("0.24") ],
        [ BigDecimal("394600"), BigDecimal("0.32") ],
        [ BigDecimal("501050"), BigDecimal("0.35") ],
        [ BigDecimal("751600"), BigDecimal("0.37") ]
      ]
    }
  }.freeze

  SOCIAL_SECURITY_RATE = BigDecimal("0.062")
  SOCIAL_SECURITY_WAGE_BASE = {
    2025 => BigDecimal("176100")
  }.freeze

  MEDICARE_RATE = BigDecimal("0.0145")
  ADDITIONAL_MEDICARE_RATE = BigDecimal("0.009")
  ADDITIONAL_MEDICARE_THRESHOLD = {
    "single" => BigDecimal("200000"),
    "married_filing_jointly" => BigDecimal("250000")
  }.freeze

  Estimate = Data.define(:total, :federal, :fica, :state, :effective_rate)

  def initialize(filing_status: "single", year: 2025, state_rate: 5.0)
    @filing_status = VALID_FILING_STATUSES.include?(filing_status) ? filing_status : "single"
    @year = FEDERAL_BRACKETS.key?(year) ? year : FEDERAL_BRACKETS.keys.max
    @state_rate = BigDecimal(state_rate.to_s) / BigDecimal("100")
  end

  def estimate(gross_income:)
    gross = BigDecimal(gross_income.to_s)
    return zero_estimate if gross <= 0

    federal = federal_tax(gross)
    fica = fica_tax(gross)
    state = state_tax(gross)
    total = round_money(federal + fica + state)

    Estimate.new(
      total: total,
      federal: round_money(federal),
      fica: round_money(fica),
      state: round_money(state),
      effective_rate: (total / gross * 100).round(2)
    )
  end

  private
    def zero_estimate
      zero = BigDecimal("0")
      Estimate.new(total: zero, federal: zero, fica: zero, state: zero, effective_rate: zero)
    end

    def federal_tax(gross)
      taxable = [ gross - standard_deduction, BigDecimal("0") ].max
      brackets = FEDERAL_BRACKETS[@year][@filing_status]

      tax = BigDecimal("0")
      brackets.each_with_index do |(lower_bound, rate), index|
        break if taxable <= lower_bound

        upper_bound = brackets[index + 1]&.first || taxable
        tax += ([ taxable, upper_bound ].min - lower_bound) * rate
      end
      tax
    end

    def fica_tax(gross)
      social_security = [ gross, SOCIAL_SECURITY_WAGE_BASE[@year] ].min * SOCIAL_SECURITY_RATE
      medicare = gross * MEDICARE_RATE
      additional_medicare_threshold = ADDITIONAL_MEDICARE_THRESHOLD[@filing_status]
      additional_medicare = [ gross - additional_medicare_threshold, BigDecimal("0") ].max * ADDITIONAL_MEDICARE_RATE

      social_security + medicare + additional_medicare
    end

    # Simplification: real state tax systems vary widely (brackets, deductions,
    # some states have none at all). A flat rate on gross is close enough for
    # planning-grade estimates.
    def state_tax(gross)
      gross * @state_rate
    end

    def standard_deduction
      STANDARD_DEDUCTION[@year][@filing_status]
    end

    def round_money(amount)
      amount.round(2)
    end
end
