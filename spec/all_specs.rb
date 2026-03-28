# =============================================================
# SPECS — TDD com RSpec, FactoryBot, Shoulda Matchers
# =============================================================

# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start 'rails' if ENV['COVERAGE']

# spec/rails_helper.rb (trecho relevante)
# RSpec.configure do |config|
#   config.include FactoryBot::Syntax::Methods
#   config.include Devise::Test::ControllerHelpers, type: :controller
# end
# Shoulda::Matchers.configure do |config|
#   config.integrate { |with| with.test_framework(:rspec).library(:rails) }
# end

# ── Factories ─────────────────────────────────────────────────
# spec/factories/pipes.rb
FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
  end

  factory :pipe do
    association :organization
    name { Faker::Lorem.words(number: 3).join(" ") }
    slug { Faker::Internet.slug }

    # Trait para pipe com fases padrão
    trait :with_phases do
      after(:create) do |pipe|
        create(:phase, pipe:, name: "Início", position: 1)
        create(:phase, pipe:, name: "Em Andamento", position: 2)
        create(:phase, pipe:, name: "Concluído", position: 3)
      end
    end
  end

  factory :phase do
    association :pipe
    name     { Faker::Lorem.word }
    position { Faker::Number.between(from: 1, to: 100) }
  end

  factory :user do
    name  { Faker::Name.full_name }
    email { Faker::Internet.unique.email }
  end

  factory :card do
    association :phase
    title { Faker::Lorem.sentence(word_count: 4) }

    trait :overdue do
      due_date { 3.days.ago }
    end

    trait :with_assignee do
      association :assignee, factory: :user
    end
  end
end

# ── Model Specs ───────────────────────────────────────────────
# spec/models/card_spec.rb
RSpec.describe Card do
  # Shoulda Matchers — conciso e legível
  describe "associations" do
    it { is_expected.to belong_to(:phase) }
    it { is_expected.to belong_to(:assignee).optional }
    it { is_expected.to have_many(:comments).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe "scopes" do
    let(:pipe) { create(:pipe) }
    let(:phase) { create(:phase, pipe:) }

    describe ".overdue" do
      it "retorna apenas cards vencidos" do
        overdue = create(:card, :overdue, phase:)
        future  = create(:card, due_date: 1.week.from_now, phase:)

        expect(Card.overdue).to include(overdue)
        expect(Card.overdue).not_to include(future)
      end
    end
  end

  describe "#overdue?" do
    it { expect(build(:card, :overdue)).to be_overdue }
    it { expect(build(:card, due_date: nil)).not_to be_overdue }
  end
end

# ── Service Specs ─────────────────────────────────────────────
# spec/services/cards/move_service_spec.rb
RSpec.describe Cards::MoveService do
  let(:pipe)   { create(:pipe) }
  let(:phase1) { create(:phase, pipe:, position: 1) }
  let(:phase2) { create(:phase, pipe:, position: 2) }
  let(:card)   { create(:card, phase: phase1) }

  subject(:result) { described_class.new(card:, destination_phase: phase2).call }

  context "quando movimento é válido" do
    it "move o card para a fase de destino" do
      expect { result }.to change { card.reload.phase }.from(phase1).to(phase2)
    end

    it "retorna sucesso" do
      expect(result).to be_success
    end

    it "publica evento Kafka" do
      expect(CardEventProducer).to receive(:card_moved).with(card:, from_phase: phase1)
      result
    end
  end

  context "quando o card já está na fase de destino" do
    subject(:result) { described_class.new(card:, destination_phase: phase1).call }

    it "não move o card" do
      expect { result }.not_to change { card.reload.phase_id }
    end

    it "retorna falha" do
      expect(result).not_to be_success
    end

    it "inclui mensagem de erro" do
      expect(result.errors).to include("Card já está nesta fase")
    end
  end

  context "quando a fase pertence a um pipe diferente" do
    let(:other_phase) { create(:phase) }  # pipe diferente

    subject(:result) { described_class.new(card:, destination_phase: other_phase).call }

    it "retorna falha" do
      expect(result).not_to be_success
      expect(result.errors).to include("Fase de destino não pertence ao mesmo pipe")
    end
  end
end

# ── GraphQL Specs ─────────────────────────────────────────────
# spec/graphql/mutations/move_card_spec.rb
RSpec.describe Mutations::MoveCard, type: :graphql do
  let(:user)   { create(:user) }
  let(:pipe)   { create(:pipe, :with_phases) }
  let(:card)   { create(:card, phase: pipe.phases.first) }
  let(:destination) { pipe.phases.second }

  let(:mutation) do
    <<~GQL
      mutation MoveCard($cardId: ID!, $destinationPhaseId: ID!) {
        moveCard(cardId: $cardId, destinationPhaseId: $destinationPhaseId) {
          card { id title }
          errors
        }
      }
    GQL
  end

  subject(:result) do
    RailsSchema.execute(
      mutation,
      variables: { cardId: card.id, destinationPhaseId: destination.id },
      context: { current_user: user }
    )
  end

  it "move o card com sucesso" do
    data = result.dig("data", "moveCard")
    expect(data["errors"]).to be_empty
    expect(data["card"]["id"]).to eq(card.id.to_s)
    expect(card.reload.phase).to eq(destination)
  end
end

# ── Domain Entity Specs — zero Rails ─────────────────────────
# spec/domain/entities/card_spec.rb
RSpec.describe Domain::Card do
  let(:pipe_phases) { [1, 2, 3] }  # IDs das phases do pipe

  subject(:card) { described_class.new(id: 1, title: "Tarefa", phase_id: 1) }

  describe "#move_to!" do
    it "muda a phase" do
      card.move_to!(2, pipe_phases:)
      expect(card.phase_id).to eq(2)
    end

    it "registra um Domain Event" do
      card.move_to!(2, pipe_phases:)
      expect(card.events.last).to be_a(Domain::CardMoved)
      expect(card.events.last.from_phase_id).to eq(1)
      expect(card.events.last.to_phase_id).to eq(2)
    end

    it "levanta DomainError quando fase não pertence ao pipe" do
      expect { card.move_to!(99, pipe_phases:) }.to raise_error(DomainError)
    end

    it "levanta DomainError quando já está na fase" do
      expect { card.move_to!(1, pipe_phases:) }.to raise_error(DomainError)
    end
  end
end

# ── Consumer Specs ────────────────────────────────────────────
# spec/consumers/card_events_consumer_spec.rb
RSpec.describe CardEventsConsumer do
  subject(:consumer) { described_class.new }

  describe "#consume" do
    let(:message) do
      double(
        payload: { 'event' => 'card.moved', 'card_id' => 1, 'from_phase_id' => 1, 'to_phase_id' => 2, 'occurred_at' => Time.current.iso8601 },
        topic: 'card_events',
        partition: 0,
        offset: 42
      )
    end

    before do
      allow(consumer).to receive(:messages).and_return([message])
      allow(Redis.current).to receive(:get).and_return(nil)
      allow(Redis.current).to receive(:setex)
    end

    it "chama o handler correto" do
      expect(Cards::HandleMovedEvent).to receive(:new).and_return(double(call: true))
      consumer.consume
    end

    context "quando evento já foi processado (idempotência)" do
      before { allow(Redis.current).to receive(:get).and_return('1') }

      it "não processa o evento novamente" do
        expect(Cards::HandleMovedEvent).not_to receive(:new)
        consumer.consume
      end
    end
  end
end
