# ⚙️ Módulo 5 – Outros Tópicos Importantes

## 1. RESTful API + JBuilder

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :posts, only: [:index, :show, :create, :update, :destroy]
    resources :users, only: [:show, :update]
  end
end

# app/controllers/api/v1/posts_controller.rb
module Api
  module V1
    class PostsController < ApplicationController
      def index
        @posts = Post.published
                     .includes(:user, :tags)
                     .page(params[:page]).per(params[:per_page] || 20)
        render :index
      end

      def show
        @post = Post.find(params[:id])
        render :show
      end
    end
  end
end

# app/views/api/v1/posts/index.json.jbuilder
json.data do
  json.array! @posts do |post|
    json.partial! "api/v1/posts/post", post: post
  end
end

json.meta do
  json.current_page @posts.current_page
  json.total_pages  @posts.total_pages
  json.total_count  @posts.total_count
end

# app/views/api/v1/posts/_post.json.jbuilder
json.extract! post, :id, :title, :body, :status, :created_at

json.author do
  json.extract! post.user, :id, :name, :email
end

json.tags post.tags do |tag|
  json.extract! tag, :id, :name
end
```

---

## 2. Background Jobs com Sidekiq

```ruby
# Gemfile
gem 'sidekiq'
gem 'redis'

# config/application.rb
config.active_job.queue_adapter = :sidekiq

# app/jobs/email_notification_job.rb
class EmailNotificationJob < ApplicationJob
  queue_as :default
  retry_on Net::OpenTimeout, wait: :exponentially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id, email_type)
    user = User.find(user_id)
    UserMailer.send(email_type, user).deliver_now
  end
end

# Uso
EmailNotificationJob.perform_later(user.id, :welcome)
EmailNotificationJob.set(wait: 1.hour).perform_later(user.id, :reminder)
EmailNotificationJob.set(wait_until: Date.tomorrow.noon).perform_later(user.id, :followup)

# Worker Sidekiq puro (mais controle)
class HeavyReportWorker
  include Sidekiq::Worker
  sidekiq_options queue: :reports, retry: 3

  def perform(report_id)
    report = Report.find(report_id)
    ReportGenerator.call(report)
    report.update!(status: :completed)
  end
end

# Enfileirar
HeavyReportWorker.perform_async(report.id)
HeavyReportWorker.perform_in(5.minutes, report.id)
HeavyReportWorker.perform_at(Time.zone.parse("2024-12-25 00:00"), report.id)
```

---

## 3. Autenticação com Devise

```ruby
# Gemfile: gem 'devise'
# rails generate devise:install
# rails generate devise User

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :trackable
end

# routes.rb
devise_for :users

# Controller
class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  def current_user  # disponível automaticamente pelo Devise
    super
  end
end

# Helper methods do Devise
user_signed_in?
current_user
before_action :authenticate_user!
```

---

## 4. JWT (JSON Web Token)

```ruby
# app/services/jwt_service.rb
class JwtService
  SECRET = Rails.application.credentials.secret_key_base
  ALGORITHM = "HS256"
  EXPIRY = 24.hours

  def self.encode(payload)
    payload[:exp] = EXPIRY.from_now.to_i
    JWT.encode(payload, SECRET, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET, true, algorithm: ALGORITHM)
    HashWithIndifferentAccess.new(decoded.first)
  rescue JWT::DecodeError => e
    raise AuthenticationError, "Token inválido: #{e.message}"
  rescue JWT::ExpiredSignature
    raise AuthenticationError, "Token expirado"
  end
end

# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    token = request.headers["Authorization"]&.split(" ")&.last
    raise AuthenticationError, "Token ausente" unless token

    payload = JwtService.decode(token)
    @current_user = User.find(payload[:user_id])
  rescue AuthenticationError => e
    render json: { error: e.message }, status: :unauthorized
  end

  def current_user
    @current_user
  end
end

# app/controllers/api/v1/sessions_controller.rb
class Api::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_request!

  def create
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
      token = JwtService.encode(user_id: user.id)
      render json: { token: token, user: user }, status: :ok
    else
      render json: { error: "Credenciais inválidas" }, status: :unauthorized
    end
  end
end
```

---

## 5. Cache (Rails.cache)

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV["REDIS_URL"],
  expires_in: 1.hour
}

# Uso básico
Rails.cache.write("chave", valor, expires_in: 30.minutes)
Rails.cache.read("chave")
Rails.cache.delete("chave")
Rails.cache.exist?("chave")

# fetch: lê do cache ou executa bloco e armazena
def trending_posts
  Rails.cache.fetch("posts/trending", expires_in: 15.minutes) do
    Post.published.order(views_count: :desc).limit(10).to_a
  end
end

# Cache de fragmento (views)
# <%# expire quando post.updated_at mudar %>
# <% cache post do %>
#   <%= render post %>
# <% end %>

# Russian Doll Caching (aninhado)
# <% cache ["posts-list", Post.maximum(:updated_at)] do %>
#   <% @posts.each do |post| %>
#     <% cache post do %>
#       ...
#     <% end %>
#   <% end %>
# <% end %>

# Invalidar cache
Rails.cache.delete_matched("posts/*")

# Low-level cache com Memcached/Redis
Post.count  # SELECT COUNT(*) ...
Rails.cache.fetch("posts_count", expires_in: 5.minutes) { Post.count }
```

---

## 6. SOLID e Boas Práticas em Rails

### S – Single Responsibility

```ruby
# ❌ Controller fazendo tudo
def create
  user = User.new(user_params)
  if user.save
    UserMailer.welcome(user).deliver_later
    SlackNotifier.notify("#signups", "Novo usuário: #{user.email}")
    Analytics.track(user, :signed_up)
    render json: user
  end
end

# ✅ Service Object
class UserRegistrationService
  def initialize(params)
    @params = params
  end

  def call
    user = User.new(@params)
    return failure(user.errors) unless user.save
    notify(user)
    success(user)
  end

  private

  def notify(user)
    UserMailer.welcome(user).deliver_later
    SlackNotifier.notify("#signups", "Novo: #{user.email}")
  end

  def success(user) = { success: true, user: user }
  def failure(errors) = { success: false, errors: errors }
end

# Controller limpo
def create
  result = UserRegistrationService.new(user_params).call
  if result[:success]
    render json: result[:user], status: :created
  else
    render json: { errors: result[:errors] }, status: :unprocessable_entity
  end
end
```

### O – Open/Closed

```ruby
# ❌ if/elsif para cada tipo de notificação
def notificar(tipo, mensagem)
  if tipo == :email
    Mailer.send(mensagem)
  elsif tipo == :sms
    SMSService.send(mensagem)
  elsif tipo == :push
    PushService.send(mensagem)
  end
end

# ✅ Polimorfismo
class EmailNotifier
  def notify(mensagem) = Mailer.send(mensagem)
end

class SmsNotifier
  def notify(mensagem) = SMSService.send(mensagem)
end

class PushNotifier
  def notify(mensagem) = PushService.send(mensagem)
end

def notificar(notifier, mensagem)
  notifier.notify(mensagem)   # aberto para extensão, fechado para modificação
end
```

### L – Liskov Substitution

```ruby
# Subclasses devem poder substituir a classe pai
class Animal
  def falar = raise NotImplementedError
end

class Cachorro < Animal
  def falar = "Au!"
end

class Gato < Animal
  def falar = "Miau!"
end

# Qualquer Animal pode ser usado onde Animal é esperado
[Cachorro.new, Gato.new].each { |a| puts a.falar }
```

### I – Interface Segregation

```ruby
# ❌ Interface gorda
module Exportavel
  def to_pdf = raise NotImplementedError
  def to_csv = raise NotImplementedError
  def to_xlsx = raise NotImplementedError
end

# ✅ Interfaces menores e específicas
module PdfExportavel
  def to_pdf = raise NotImplementedError
end

module CsvExportavel
  def to_csv = raise NotImplementedError
end

class Relatorio
  include CsvExportavel   # só o que precisa
  def to_csv = "id,nome\n..."
end
```

### D – Dependency Inversion

```ruby
# ❌ Dependência direta de implementação concreta
class OrderProcessor
  def process(order)
    StripeGateway.charge(order.total)   # acoplado ao Stripe!
  end
end

# ✅ Depende de abstração (injeção de dependência)
class OrderProcessor
  def initialize(payment_gateway)
    @gateway = payment_gateway
  end

  def process(order)
    @gateway.charge(order.total)   # funciona com qualquer gateway
  end
end

OrderProcessor.new(StripeGateway.new).process(order)
OrderProcessor.new(PaypalGateway.new).process(order)
OrderProcessor.new(MockGateway.new).process(order)   # testes!
```
