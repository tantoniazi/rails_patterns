# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::UseCases::TransferFunds do
  let(:from_user) { create(:user) }
  let(:to_user) { create(:user) }

  before do
    from_user.account.update!(balance: 100)
    to_user.account.update!(balance: 50)
  end

  it "transfers funds between accounts" do
    result = described_class.new.call(
      from_user: from_user,
      to_user_id: to_user.id,
      amount: 30
    )

    expect(result).to be_success
    expect(from_user.account.reload.balance).to eq(70)
    expect(to_user.account.reload.balance).to eq(80)
  end

  it "fails when insufficient funds" do
    result = described_class.new.call(
      from_user: from_user,
      to_user_id: to_user.id,
      amount: 200
    )

    expect(result).to be_failure
    expect(result.errors).to include("Insufficient funds")
    expect(from_user.account.reload.balance).to eq(100)
  end

  it "fails for invalid amount" do
    result = described_class.new.call(
      from_user: from_user,
      to_user_id: to_user.id,
      amount: -10
    )

    expect(result).to be_failure
    expect(result.errors).to include("Amount must be positive")
  end
end
