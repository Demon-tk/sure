require "test_helper"

class DebtPayoffPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "redirects users without preview access" do
    disable_preview_features

    get debt_payoff_plan_url

    assert_redirected_to root_path
  end

  test "renders for users with preview access" do
    enable_preview_features

    get debt_payoff_plan_url

    assert_response :success
    assert_match I18n.t("debt_payoff_plans.show.title"), response.body
  end

  test "shows a needs-info badge for a liability without rate or minimum" do
    enable_preview_features

    get debt_payoff_plan_url

    assert_match I18n.t("debt_payoff_plans.show.debt_list.needs_info"), response.body
  end

  test "honors strategy and extra payment params and override params clear the needs-info badge" do
    enable_preview_features

    get debt_payoff_plan_url(
      strategy: "snowball",
      extra_payment: 250,
      overrides: { accounts(:other_liability).id => { rate: "10", minimum_payment: "50" } }
    )

    assert_response :success
    assert_no_match I18n.t("debt_payoff_plans.show.debt_list.needs_info"), response.body
  end

  test "honors the expected_return param and renders the invest-vs-payoff verdict" do
    enable_preview_features

    get debt_payoff_plan_url(expected_return: 3)

    assert_response :success
    assert_match I18n.t("debt_payoff_plans.show.verdict.tossup"), response.body
  end

  private
    def enable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end

    def disable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))
    end
end
