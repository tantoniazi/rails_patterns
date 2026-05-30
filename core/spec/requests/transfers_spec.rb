# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Transfers", type: :request do
  let(:from_user) { create(:user) }
  let(:to_user) { create(:user) }
  let(:headers) { auth_headers(from_user) }

  before do
    from_user.account.update!(balance: 100)
    to_user.account.update!(balance: 0)
  end

  describe "POST /api/v1/transfers" do
    it "transfers funds" do
      post "/api/v1/transfers",
           params: { transfer: { to_user_id: to_user.id, amount: 25.50 } },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["amount"]).to eq("25.5")
      expect(from_user.account.reload.balance).to eq(74.5)
      expect(to_user.account.reload.balance).to eq(25.5)
    end

    it "returns error for insufficient funds" do
      post "/api/v1/transfers",
           params: { transfer: { to_user_id: to_user.id, amount: 500 } },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
