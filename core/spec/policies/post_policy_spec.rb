# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostPolicy do
  subject(:policy) { described_class.new(user, post) }

  let(:owner) { create(:user) }
  let(:post) { create(:post, user: owner) }

  context "when user is the owner" do
    let(:user) { owner }

    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  context "when user is admin" do
    let(:user) { create(:user, :admin) }

    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be true }
  end

  context "when user is moderator with permission" do
    let(:user) { create(:user, :moderator) }

    before { create(:permission, role: "moderator", resource: "post", action: "update") }

    it { expect(policy.update?).to be true }
    it { expect(policy.destroy?).to be false }
  end

  context "when user is another member" do
    let(:user) { create(:user) }

    it { expect(policy.update?).to be false }
    it { expect(policy.destroy?).to be false }
  end
end
