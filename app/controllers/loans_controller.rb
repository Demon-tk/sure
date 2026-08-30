class LoansController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :subtype, :rate_type, :interest_rate, :term_months, :initial_balance, :minimum_payment,
    rate_changes: [ :effective_on, :rate ]
  )
end
