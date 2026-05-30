# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApplicationController
      def create
        result = Domain::UseCases::AuthenticateUser.new.call(
          email: session_params[:email],
          password: session_params[:password]
        )

        if result.success?
          @tokens = result.value[:tokens]
          @user = result.value[:user]
          render :create, status: :created
        else
          render json: { errors: result.errors }, status: :unauthorized
        end
      end

      def destroy
        head :no_content
      end

      def refresh
        tokens = Infrastructure::Auth::JwtService.refresh(params.require(:refresh_token))

        if tokens
          @tokens = tokens
          render :refresh
        else
          render json: { error: "Invalid refresh token" }, status: :unauthorized
        end
      end

      private

      def session_params
        params.require(:session).permit(:email, :password)
      end
    end
  end
end
