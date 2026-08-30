require "test_helper"

class FirePlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "redirects users without preview access" do
    disable_preview_features

    get fire_plan_url

    assert_redirected_to root_path
  end

  test "renders for users with preview access" do
    enable_preview_features

    get fire_plan_url

    assert_response :success
    assert_match I18n.t("fire_plans.show.title"), response.body
  end

  test "honors assumption params" do
    enable_preview_features

    get fire_plan_url(swr: 3, current_age: 40, filing_status: "married_filing_jointly")

    assert_response :success
    assert_match I18n.t("fire_plans.show.title"), response.body
  end

  private
    def enable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end

    def disable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))
    end
end
