# 🏗️ Módulo 10 – Design Patterns em Rails

---

## 1. Service Object (já visto, aprofundando)

```ruby
# Padrão: encapsula uma operação de negócio complexa
# Quando usar: lógica que não pertence ao model nem ao controller

# app/services/transfer_funds_service.rb
class TransferFundsService
  Result = Struct.new(:success?, :error, keyword_init: true)

  def initialize(from:, to:, amount:)
    @from   = from
    @to     = to
    @amount = amount
  end

  def call
    validate!
    transfer!
    Result.new(success?: true, error: nil)
  rescue InsufficientFundsError, ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

  def validate!
    raise ArgumentError, "Valor deve ser positivo" unless @amount.positive?
    raise InsufficientFundsError, "Saldo insuficiente" if @from.balance < @amount
  end

  def transfer!
    ActiveRecord::Base.transaction do
      @from.decrement!(:balance, @amount)
      @to.increment!(:balance, @amount)
      Transfer.create!(from: @from, to: @to, amount: @amount)
    end
  end
end

# Uso
result = TransferFundsService.new(from: conta_a, to: conta_b, amount: 100).call
result.success?  # true / false
result.error     # nil / "mensagem"
```

---

## 2. Decorator (Draper / PORO)

```ruby
# Problema: view logic vazando para model ou helper
# Solução: Decorator envolve o model com apresentação

# Sem gem (PORO Decorator)
# app/decorators/user_decorator.rb
class UserDecorator < SimpleDelegator
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def avatar_url
    if super.present?
      super
    else
      "https://ui-avatars.com/api/?name=#{URI.encode(full_name)}"
    end
  end

  def member_since
    created_at.strftime("%B %Y")
  end

  def role_badge
    case role
    when "admin"     then "🔴 Admin"
    when "moderator" then "🟡 Moderador"
    else                  "🟢 Membro"
    end
  end

  def truncated_bio(length: 100)
    bio.to_s.truncate(length)
  end
end

# Uso no controller
def show
  @user = UserDecorator.new(User.find(params[:id]))
end

# Na view
@user.full_name     # "Maria Silva"
@user.role_badge    # "🔴 Admin"
@user.member_since  # "January 2024"

# Com Draper
# gem 'draper'
class UserDecorator < Draper::Decorator
  delegate_all

  def full_name = "#{first_name} #{last_name}"
end
User.find(1).decorate  # retorna UserDecorator
User.all.decorate      # retorna coleção decorada
```

---

## 3. Observer / Event (dry-events / ActiveSupport::Notifications)

```ruby
# Problema: modelo com callbacks que disparam ações não relacionadas
# Solução: Observer desacopla efeitos colaterais

# Com ActiveSupport::Notifications (pub/sub nativo do Rails)
# app/services/event_publisher.rb
class EventPublisher
  def self.publish(event, payload = {})
    ActiveSupport::Notifications.instrument("app.#{event}", payload)
  end
end

# app/observers/user_observer.rb
class UserObserver
  def self.subscribe!
    ActiveSupport::Notifications.subscribe("app.user.created") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      user  = event.payload[:user]
      UserMailer.welcome(user).deliver_later
      SlackNotifier.post("#signups", "Novo usuário: #{user.email}")
    end

    ActiveSupport::Notifications.subscribe("app.post.published") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      post  = event.payload[:post]
      post.followers.each { |f| NotificationService.notify(f, post) }
    end
  end
end

# config/initializers/observers.rb
UserObserver.subscribe!

# No service/model
EventPublisher.publish("user.created", user: user)
EventPublisher.publish("post.published", post: post)

# Vantagem: User e Post não sabem nada de email, slack, notificações
```

---

## 4. Strategy Pattern

```ruby
# Problema: múltiplas variações de um algoritmo
# Solução: encapsula cada variação em uma classe separada

# Exemplo: diferentes estratégias de precificação
module Pricing
  class Standard
    def calculate(product, quantity)
      product.base_price * quantity
    end
  end

  class Bulk
    TIERS = { 10 => 0.90, 50 => 0.80, 100 => 0.70 }.freeze

    def calculate(product, quantity)
      discount = TIERS.select { |min, _| quantity >= min }.values.last || 1.0
      product.base_price * quantity * discount
    end
  end

  class Subscription
    def calculate(product, quantity)
      product.base_price * quantity * 0.75
    end
  end
end

class Order
  def initialize(strategy: Pricing::Standard.new)
    @strategy = strategy
  end

  def total(product, quantity)
    @strategy.calculate(product, quantity)
  end
end

# Uso
order = Order.new(strategy: Pricing::Bulk.new)
order.total(produto, 50)   # aplica desconto bulk
```

---

## 5. Command Pattern

```ruby
# Problema: operações que precisam ser desfeitas (undo) ou auditadas
# Solução: encapsula a ação + o desfazer em um objeto

class PublishPostCommand
  attr_reader :post, :previous_status

  def initialize(post)
    @post            = post
    @previous_status = post.status
  end

  def execute
    @post.update!(status: :published, published_at: Time.current)
    AuditLog.create!(action: "post_published", resource: @post, user: Current.user)
  end

  def undo
    @post.update!(status: @previous_status, published_at: nil)
    AuditLog.create!(action: "post_unpublished", resource: @post, user: Current.user)
  end
end

# Uso
cmd = PublishPostCommand.new(post)
cmd.execute   # publica
cmd.undo      # reverte
```

---

## 6. Repository Pattern

```ruby
# Problema: queries espalhadas por todo o código
# Solução: centraliza o acesso a dados em uma classe

# app/repositories/post_repository.rb
class PostRepository
  def find(id)
    Post.find(id)
  end

  def find_published(page: 1, per: 20)
    Post.published
        .includes(:user, :tags)
        .order(published_at: :desc)
        .page(page).per(per)
  end

  def find_by_author(user, page: 1)
    Post.where(user: user)
        .order(created_at: :desc)
        .page(page)
  end

  def search(query, page: 1)
    Post.published
        .where("title ILIKE ? OR body ILIKE ?", "%#{query}%", "%#{query}%")
        .page(page)
  end

  def trending(limit: 5)
    Post.published
        .where("published_at > ?", 7.days.ago)
        .order(views_count: :desc)
        .limit(limit)
  end
end

# Uso
repo = PostRepository.new
repo.find_published(page: 2)
repo.trending(limit: 10)
```

---

## 7. Form Object

```ruby
# Problema: formulário que atualiza múltiplos modelos ao mesmo tempo
# Solução: Form Object centraliza validações e lógica do form

# app/forms/registration_form.rb
class RegistrationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name,                  :string
  attribute :email,                 :string
  attribute :password,              :string
  attribute :password_confirmation, :string
  attribute :company_name,          :string
  attribute :plan,                  :string, default: "free"

  validates :name,     presence: true
  validates :email,    presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 },
                       confirmation: true
  validates :company_name, presence: true

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      company = Company.create!(name: company_name, plan: plan)
      user    = company.users.create!(name: name, email: email, password: password)
      WelcomeMailer.send_to(user).deliver_later
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end
end

# No controller
def create
  @form = RegistrationForm.new(registration_params)
  if @form.save
    redirect_to dashboard_path, notice: "Conta criada!"
  else
    render :new
  end
end

def registration_params
  params.require(:registration).permit(:name, :email, :password,
                                       :password_confirmation, :company_name, :plan)
end
```

---

## 8. Interactor (dry-transaction / Interactor gem)

```ruby
# Encadeia múltiplos serviços em um pipeline
# gem 'interactor'

class PlaceOrder
  include Interactor::Organizer

  organize ValidateOrder,
           ReserveInventory,
           ChargePayment,
           CreateOrder,
           SendConfirmationEmail
end

class ValidateOrder
  include Interactor

  def call
    context.fail!(error: "Itens inválidos") unless context.items.any?
    context.fail!(error: "Usuário bloqueado") if context.user.blocked?
  end
end

class ChargePayment
  include Interactor

  def call
    result = PaymentGateway.charge(context.user, context.total)
    context.payment_id = result.id
  rescue PaymentGateway::Error => e
    context.fail!(error: e.message)
  end

  def rollback
    PaymentGateway.refund(context.payment_id) if context.payment_id
  end
end

# Uso
result = PlaceOrder.call(user: current_user, items: cart.items, total: cart.total)

if result.success?
  redirect_to order_path(result.order)
else
  flash[:error] = result.error
  redirect_to cart_path
end
```

---

## 9. Presenter

```ruby
# Separa dados de apresentação de uma view complexa (ex: dashboard)
# app/presenters/dashboard_presenter.rb
class DashboardPresenter
  def initialize(user, range: 30.days)
    @user  = user
    @range = range
    @since = range.ago
  end

  def total_revenue
    @total_revenue ||= @user.orders.paid.where("created_at > ?", @since).sum(:total)
  end

  def revenue_growth
    previous = @user.orders.paid
                    .where(created_at: (@range * 2).ago..@since)
                    .sum(:total)
    return 0 if previous.zero?
    ((total_revenue - previous) / previous * 100).round(1)
  end

  def top_products
    @top_products ||= @user.order_items
                           .joins(:product)
                           .where("order_items.created_at > ?", @since)
                           .group("products.id", "products.name")
                           .order("COUNT(*) DESC")
                           .limit(5)
                           .count
  end

  def recent_orders
    @recent_orders ||= @user.orders.paid
                            .includes(:items)
                            .order(created_at: :desc)
                            .limit(10)
  end
end

# No controller
def dashboard
  @presenter = DashboardPresenter.new(current_user)
end

# Na view
@presenter.total_revenue
@presenter.revenue_growth
@presenter.top_products
```
