require "test_helper"

class CreditCardTest < ActiveSupport::TestCase
  test "payoff rate and minimum come from the stored apr and minimum payment" do
    credit_card = accounts(:credit_card).credit_card

    assert_equal credit_card.apr, credit_card.payoff_rate
    assert_equal credit_card.minimum_payment, credit_card.payoff_minimum_payment
  end

  test "a card without an apr reports no payoff rate" do
    credit_card = accounts(:credit_card).credit_card
    credit_card.update!(apr: nil, minimum_payment: nil)

    assert_nil credit_card.payoff_rate
    assert_nil credit_card.payoff_minimum_payment
  end
end
