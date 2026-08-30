# One generic life event for the FIRE planner. A house purchase, a child, a
# spouse's income starting or stopping, an inheritance — these are all
# instances of FireMilestone, not subclasses. Each one nudges income,
# expenses, or the portfolio by a one-time or annual amount over an age
# window; FirePlan::Projector is responsible for folding that into the
# year-by-year projection.
class FireMilestone < ApplicationRecord
  belongs_to :family

  AFFECTS = %w[income expenses portfolio].freeze

  validates :name, presence: true
  validates :affects, inclusion: { in: AFFECTS }
  validates :start_age, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 16, less_than_or_equal_to: 100 }
  validates :end_age, numericality: { only_integer: true, greater_than_or_equal_to: 16, less_than_or_equal_to: 100 }, allow_nil: true
  validates :one_time_amount, numericality: true
  validates :annual_amount, numericality: true
  validate :end_age_not_before_start_age

  scope :active, -> { where(active: true) }

  # Whether this milestone is "in effect" at the given age, for annual
  # amounts. A milestone with no end_age is a single-year event (e.g. a
  # windfall booked as an annual bump the year it lands), so it only covers
  # its start_age.
  def covers?(age)
    return false unless active?
    return false if age < start_age

    end_age.nil? ? age == start_age : age <= end_age
  end

  private
    def end_age_not_before_start_age
      return if end_age.nil? || start_age.nil?

      errors.add(:end_age, "must be greater than or equal to start age") if end_age < start_age
    end
end
