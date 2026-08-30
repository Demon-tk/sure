require "test_helper"

class PlanScenariosControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "redirects users without preview access" do
    disable_preview_features

    post plan_scenarios_url, params: { plan_scenario: valid_scenario_params }

    assert_redirected_to root_path
    assert_equal 1, @user.family.plan_scenarios.count
  end

  test "create with valid params saves a family scenario and redirects" do
    enable_preview_features

    assert_difference -> { @user.family.plan_scenarios.count }, +1 do
      post plan_scenarios_url, params: { plan_scenario: valid_scenario_params }
    end

    scenario = @user.family.plan_scenarios.order(:created_at).last
    assert_equal "Coast FI", scenario.name
    assert_equal "/fire_plan?retire_age=55", scenario.path
    assert_redirected_to plan_path
  end

  test "create with invalid params (blank name) redirects with an alert" do
    enable_preview_features

    assert_no_difference -> { @user.family.plan_scenarios.count } do
      post plan_scenarios_url, params: { plan_scenario: valid_scenario_params.merge(name: "") }
    end

    assert_redirected_to plan_path
    assert flash[:alert].present?
  end

  test "create rejects an absolute URL path" do
    enable_preview_features

    assert_no_difference -> { @user.family.plan_scenarios.count } do
      post plan_scenarios_url, params: { plan_scenario: valid_scenario_params.merge(path: "https://evil.example") }
    end

    assert_redirected_to plan_path
    assert flash[:alert].present?
  end

  test "destroy removes a scenario owned by the family" do
    enable_preview_features

    scenario = plan_scenarios(:retire_early)

    assert_difference -> { @user.family.plan_scenarios.count }, -1 do
      delete plan_scenario_url(scenario)
    end

    assert_redirected_to plan_path
    assert_raises(ActiveRecord::RecordNotFound) { scenario.reload }
  end

  test "destroy of another family's scenario returns not found" do
    enable_preview_features

    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    foreign_scenario = other_family.plan_scenarios.create!(
      name: "Foreign plan",
      path: "/debt_payoff_plan?months=60"
    )

    delete plan_scenario_url(foreign_scenario)

    assert_response :not_found
    assert foreign_scenario.reload.persisted?
  end

  private
    def valid_scenario_params
      {
        name: "Coast FI",
        path: "/fire_plan?retire_age=55"
      }
    end

    def enable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end

    def disable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))
    end
end
