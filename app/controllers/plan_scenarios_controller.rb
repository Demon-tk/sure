class PlanScenariosController < ApplicationController
  before_action :require_preview_features!

  def create
    @scenario = Current.family.plan_scenarios.build(plan_scenario_params)

    if @scenario.save
      redirect_back fallback_location: plan_path
    else
      flash[:alert] = @scenario.errors.full_messages.to_sentence
      redirect_back fallback_location: plan_path
    end
  end

  def destroy
    Current.family.plan_scenarios.find(params[:id]).destroy
    redirect_back fallback_location: plan_path
  end

  private
    def plan_scenario_params
      params.require(:plan_scenario).permit(:name, :path)
    end
end
