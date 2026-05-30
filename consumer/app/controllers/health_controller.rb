# frozen_string_literal: true

class HealthController < ApplicationController
  def show
    render json: { status: "ok" }, status: :ok
  end
end
