# frozen_string_literal: true

module Api
  module V1
    class HealthController < ApplicationController
      def show
        render json: { status: "ok", timestamp: Time.current.iso8601 }
      end
    end
  end
end
