# Scheduled APR changes stored on a liability accountable (jsonb array of
# {"effective_on", "rate"}). Zero entries is the common case; there is no
# upper bound — an ARM with a long reset history is just a longer array.
module RateChangeable
  extend ActiveSupport::Concern

  # Normalizes form input: drops blank rows, coerces types, sorts by date.
  def rate_changes=(value)
    entries = Array(value).filter_map do |entry|
      entry = entry.to_h.stringify_keys
      next if entry["effective_on"].blank? || entry["rate"].blank?

      { "effective_on" => Date.parse(entry["effective_on"].to_s).iso8601, "rate" => entry["rate"].to_d.to_s }
    rescue Date::Error
      nil
    end

    super(entries.sort_by { |e| e["effective_on"] })
  end

  # The schedule as [[month_offset, rate], ...] for the payoff simulator,
  # where offset N means "from the Nth simulated month onward". A change
  # already in the past clamps to month 1 — it simply is the current rate.
  def payoff_rate_schedule(from: Date.current)
    Array(rate_changes).map do |entry|
      date = Date.parse(entry["effective_on"])
      offset = (date.year * 12 + date.month) - (from.year * 12 + from.month)
      [ [ offset, 1 ].max, entry["rate"].to_d ]
    end.sort_by(&:first)
  end
end
