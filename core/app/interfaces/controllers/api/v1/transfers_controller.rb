# frozen_string_literal: true

module Api
  module V1
    class TransfersController < BaseController
      def create
        authorize :transfer, :create?
        result = Domain::UseCases::TransferFunds.new.call(
          from_user: current_user,
          to_user_id: transfer_params[:to_user_id],
          amount: transfer_params[:amount]
        )

        if result.success?
          render json: result.value, status: :created
        else
          render_errors(result.errors, status: :unprocessable_entity)
        end
      end

      private

      def transfer_params
        params.require(:transfer).permit(:to_user_id, :amount)
      end
    end
  end
end
