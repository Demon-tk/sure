class AddRateChangesToLoansAndCreditCards < ActiveRecord::Migration[7.2]
  def change
    # Scheduled APR changes, any number of them: promo expirations, ARM
    # resets, servicer step-ups. Entries are {"effective_on", "rate"} hashes;
    # the payoff planner turns them into month offsets at simulation time.
    add_column :loans, :rate_changes, :jsonb, null: false, default: []
    add_column :credit_cards, :rate_changes, :jsonb, null: false, default: []
  end
end
