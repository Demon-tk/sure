# A named bookmark for a planner scenario. All planner assumptions travel as
# query params on the planner URL, so a saved scenario is just a name plus the
# relative path of the planner page (e.g. /fire_plan?retire_age=55).
class PlanScenario < ApplicationRecord
  belongs_to :family

  # Trust-boundary validation: stored paths are rendered into links and
  # navigated to later, so they must be relative planner URLs and nothing
  # else. A scheme ("https://...") or protocol-relative ("//...") value would
  # turn a saved bookmark into an open redirect to an arbitrary host.
  PATH_FORMAT = %r{\A/(?:fire_plan|debt_payoff_plan)(?:[/?#]\S*)?\z}

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :family_id }
  validates :path, presence: true, length: { maximum: 2000 }, format: { with: PATH_FORMAT }
  validate :path_must_not_be_absolute_or_protocol_relative

  private
    def path_must_not_be_absolute_or_protocol_relative
      return if path.blank?

      errors.add(:path, "must be a relative path") if path.include?("://") || path.start_with?("//")
    end
end
