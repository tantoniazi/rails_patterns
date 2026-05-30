# 🧪 Módulo 4 – Testes com RSpec, FactoryBot e TDD

## 1. Configuração Inicial

```ruby
# spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../config/environment', __dir__)
require 'rspec/rails'
require 'shoulda/matchers'
require 'factory_bot_rails'
require 'database_cleaner/active_record'

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.use_transactional_fixtures = false  # usamos DatabaseCleaner

  config.before(:suite)  { DatabaseCleaner.clean_with(:truncation) }
  config.before(:each)   { DatabaseCleaner.strategy = :transaction }
  config.before(:each)   { DatabaseCleaner.start }
  config.after(:each)    { DatabaseCleaner.clean }
end

Shoulda::Matchers.configure do |config|
  config.integrate { |with| with.test_framework(:rspec); with.library(:rails) }
end
```

---

## 2. Testes Unitários de Model

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  # Validações com shoulda-matchers
  describe "validações" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_least(2) }
  end

  # Associações com shoulda-matchers
  describe "associações" do
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to have_one(:profile) }
    it { is_expected.to belong_to(:company).optional }
  end

  # Comportamento
  describe "#full_name" do
    it "concatena nome e sobrenome" do
      user = build(:user, first_name: "Maria", last_name: "Silva")
      expect(user.full_name).to eq("Maria Silva")
    end
  end

  describe ".active" do
    it "retorna apenas usuários ativos" do
      ativo   = create(:user, active: true)
      inativo = create(:user, active: false)
      expect(User.active).to include(ativo)
      expect(User.active).not_to include(inativo)
    end
  end

  describe "#admin?" do
    it "retorna true para role admin" do
      expect(build(:user, :admin)).to be_admin
    end

    it "retorna false para role comum" do
      expect(build(:user)).not_to be_admin
    end
  end
end
```

---

## 3. Factories com FactoryBot

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    password   { "password123" }
    active     { true }

    trait :admin do
      role { "admin" }
    end

    trait :inactive do
      active { false }
    end

    trait :with_posts do
      after(:create) do |user|
        create_list(:post, 3, user: user)
      end
    end
  end
end

# spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    association :user
    title  { Faker::Lorem.sentence(word_count: 4) }
    body   { Faker::Lorem.paragraphs(number: 3).join("\n") }
    status { :draft }

    trait :published do
      status { :published }
      published_at { Time.current }
    end

    trait :with_comments do
      after(:create) do |post|
        create_list(:comment, 5, post: post)
      end
    end
  end
end

# Uso nos testes
build(:user)                       # não persiste no banco
create(:user)                      # persiste
build_stubbed(:user)               # stub (mais rápido, sem DB)
create(:user, :admin)              # trait
create(:user, email: "a@b.com")    # override
create_list(:post, 10, :published) # lista
```

---

## 4. Testes de Request (API)

```ruby
# spec/requests/posts_spec.rb
RSpec.describe "Posts API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }   # helper de autenticação

  describe "GET /api/v1/posts" do
    before { create_list(:post, 3, :published, user: user) }

    it "retorna lista de posts paginada" do
      get "/api/v1/posts", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(3)
      expect(json).to have_key("meta")
    end

    it "filtra por status" do
      create(:post, :draft, user: user)
      get "/api/v1/posts", params: { status: "published" }, headers: headers

      json = JSON.parse(response.body)
      expect(json["data"].all? { |p| p["status"] == "published" }).to be true
    end
  end

  describe "POST /api/v1/posts" do
    let(:params) { { post: { title: "Meu Post", body: "Conteúdo", status: "draft" } } }

    context "com dados válidos" do
      it "cria um post" do
        expect {
          post "/api/v1/posts", params: params, headers: headers
        }.to change(Post, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context "com dados inválidos" do
      it "retorna erros de validação" do
        post "/api/v1/posts", params: { post: { title: "" } }, headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["errors"]).to have_key("title")
      end
    end
  end
end
```

---

## 5. Stubs, Mocks e Doubles

```ruby
RSpec.describe OrderService do
  # Double: objeto substituto com interface controlada
  let(:pagamento_gateway) { double("PagamentoGateway") }
  let(:servico) { OrderService.new(gateway: pagamento_gateway) }

  describe "#processar" do
    context "quando pagamento é aprovado" do
      before do
        # Stub: define o comportamento do método
        allow(pagamento_gateway).to receive(:cobrar)
          .with(valor: 100.0, cartao: anything)
          .and_return({ status: "aprovado", id: "pay_123" })
      end

      it "confirma o pedido" do
        pedido = create(:order, valor: 100.0)
        resultado = servico.processar(pedido)
        expect(resultado).to be_success
        expect(pedido.reload.status).to eq("confirmado")
      end
    end

    context "quando pagamento falha" do
      before do
        allow(pagamento_gateway).to receive(:cobrar)
          .and_raise(PagamentoGateway::FalhaError, "Cartão recusado")
      end

      it "mantém pedido como pendente" do
        pedido = create(:order)
        servico.processar(pedido)
        expect(pedido.reload.status).to eq("pendente")
      end
    end

    it "verifica que o gateway foi chamado" do
      pedido = create(:order, valor: 50.0)
      # Mock: expectativa de chamada (verifica comportamento)
      expect(pagamento_gateway).to receive(:cobrar)
        .with(valor: 50.0, cartao: anything)
        .once
        .and_return({ status: "aprovado" })

      servico.processar(pedido)
    end
  end
end
```

---

## 6. TDD – Fluxo Red-Green-Refactor

```
1. 🔴 RED   → escreva o teste que FALHA (comportamento esperado)
2. 🟢 GREEN → escreva o MÍNIMO de código para passar
3. 🔵 BLUE  → REFATORE sem quebrar os testes
```

```ruby
# Exemplo de TDD: implementar calculadora de desconto

# PASSO 1: Red – teste falha porque a classe não existe
RSpec.describe DescontoCalculator do
  describe ".calcular" do
    it "aplica 10% para compras acima de R$100" do
      resultado = DescontoCalculator.calcular(total: 200.0, usuario: build(:user))
      expect(resultado).to eq(20.0)
    end

    it "aplica 20% para usuários VIP acima de R$100" do
      vip = build(:user, :vip)
      resultado = DescontoCalculator.calcular(total: 200.0, usuario: vip)
      expect(resultado).to eq(40.0)
    end

    it "sem desconto para compras abaixo de R$100" do
      resultado = DescontoCalculator.calcular(total: 50.0, usuario: build(:user))
      expect(resultado).to eq(0.0)
    end
  end
end

# PASSO 2: Green – implementação mínima
class DescontoCalculator
  def self.calcular(total:, usuario:)
    return 0.0 if total < 100
    percentual = usuario.vip? ? 0.20 : 0.10
    total * percentual
  end
end

# PASSO 3: Refactor – extrair constantes, melhorar nomes
class DescontoCalculator
  MINIMO_PARA_DESCONTO = 100.0
  DESCONTO_PADRAO = 0.10
  DESCONTO_VIP    = 0.20

  def self.calcular(total:, usuario:)
    return 0.0 unless elegivel?(total)
    total * percentual(usuario)
  end

  def self.elegivel?(total)
    total >= MINIMO_PARA_DESCONTO
  end
  private_class_method :elegivel?

  def self.percentual(usuario)
    usuario.vip? ? DESCONTO_VIP : DESCONTO_PADRAO
  end
  private_class_method :percentual
end
```

---

## 7. Comandos Úteis

```bash
# Rodar todos os testes
bundle exec rspec

# Teste específico
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/models/user_spec.rb:42   # linha específica

# Formato verbose
bundle exec rspec --format documentation

# Com cobertura (SimpleCov)
COVERAGE=true bundle exec rspec

# Detectar testes lentos
bundle exec rspec --profile 10
```
