class AddMinimumPaymentToLoans < ActiveRecord::Migration[7.2]
  def change
    # Same shape as credit_cards.minimum_payment. Loans need it stored, not
    # derived: servicer minimums routinely differ from the amortized payment
    # (income-driven student plans, escrowed mortgages), and no aggregator
    # supplies it for loans.
    add_column :loans, :minimum_payment, :decimal, precision: 10, scale: 2
  end
end
