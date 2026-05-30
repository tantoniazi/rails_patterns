# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      before_action :set_user, only: %i[show update]

      def me
        @user = current_user
        authorize @user
        render :show
      end

      def show
        authorize @user
      end

      def update
        authorize @user
        if @user.update(user_params)
          render :show
        else
          render_errors(@user.errors.full_messages)
        end
      end

      private

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:name, profile_attributes: %i[bio avatar_url])
      end
    end
  end
end
