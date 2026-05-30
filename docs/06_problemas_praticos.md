# 🎯 Módulo 6 – Problemas Práticos (Estilo Live Coding)

> **Dica de ouro:** Antes de codar, diga em voz alta:
> 1. O que entendi do problema
> 2. Minha abordagem
> 3. Casos extremos que vou considerar

---

## Problema 1: Endpoint com Filtros e Paginação

**Enunciado:** Crie um endpoint `GET /api/v1/products` que:
- Filtre por `category`, `min_price`, `max_price`
- Ordene por `price` ou `name`
- Retorne dados paginados (20 por página)
- Inclua metadados da paginação no response

```ruby
# app/controllers/api/v1/products_controller.rb
class Api::V1::ProductsController < ApplicationController
  def index
    @products = Product.all
    @products = apply_filters(@products)
    @products = apply_sorting(@products)
    @products = @products.page(params[:page]).per(20)

    render json: {
      data: @products.map { |p| product_json(p) },
      meta: pagination_meta(@products)
    }
  end

  private

  def apply_filters(scope)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where("price >= ?", params[:min_price]) if params[:min_price].present?
    scope = scope.where("price <= ?", params[:max_price]) if params[:max_price].present?
    scope
  end

  def apply_sorting(scope)
    allowed = %w[price name created_at]
    column = allowed.include?(params[:sort]) ? params[:sort] : "created_at"
    direction = params[:direction] == "asc" ? :asc : :desc
    scope.order(column => direction)
  end

  def product_json(product)
    {
      id: product.id,
      name: product.name,
      price: product.price,
      category: product.category
    }
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: 20
    }
  end
end
```

---

## Problema 2: Modelar Relacionamentos

**Enunciado:** Modele um sistema de reservas (hotel):
- `User` tem muitas `Reservations`
- `Room` tem muitos `Reservations`
- `Reservation` pertence a `User` e `Room`
- Uma reserva tem `check_in`, `check_out`, `status`
- Quartos não podem ser reservados no mesmo período

```ruby
# db/migrate/xxx_create_rooms.rb
create_table :rooms do |t|
  t.string  :number,   null: false
  t.integer :capacity, null: false
  t.decimal :price_per_night, precision: 10, scale: 2
  t.integer :room_type, default: 0   # enum: standard, deluxe, suite
  t.timestamps
end

# db/migrate/xxx_create_reservations.rb
create_table :reservations do |t|
  t.references :user,  null: false, foreign_key: true
  t.references :room,  null: false, foreign_key: true
  t.date    :check_in,  null: false
  t.date    :check_out, null: false
  t.integer :status, default: 0   # pending, confirmed, cancelled
  t.decimal :total_price, precision: 10, scale: 2
  t.timestamps
end

add_index :reservations, [:room_id, :check_in, :check_out]

# app/models/room.rb
class Room < ApplicationRecord
  enum room_type: { standard: 0, deluxe: 1, suite: 2 }
  has_many :reservations

  def available_for?(check_in, check_out, exclude_id: nil)
    scope = reservations.confirmed.overlapping(check_in, check_out)
    scope = scope.where.not(id: exclude_id) if exclude_id
    scope.none?
  end
end

# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :user
  belongs_to :room

  enum status: { pending: 0, confirmed: 1, cancelled: 2 }

  validates :check_in,  presence: true
  validates :check_out, presence: true
  validate  :check_out_after_check_in
  validate  :room_available

  before_create :calculate_total

  scope :overlapping, ->(check_in, check_out) {
    where("check_in < ? AND check_out > ?", check_out, check_in)
  }

  private

  def check_out_after_check_in
    return unless check_in && check_out
    errors.add(:check_out, "deve ser após o check-in") if check_out <= check_in
  end

  def room_available
    return unless room && check_in && check_out
    unless room.available_for?(check_in, check_out, exclude_id: id)
      errors.add(:room, "não está disponível para este período")
    end
  end

  def calculate_total
    noites = (check_out - check_in).to_i
    self.total_price = noites * room.price_per_night
  end
end
```

---

## Problema 3: Resolver N+1

**Enunciado:** O endpoint abaixo está lento. Identifique e corrija o N+1.

```ruby
# ❌ Versão com N+1
def index
  @orders = Order.all
  render json: @orders.map { |order|
    {
      id: order.id,
      user_name: order.user.name,           # N+1!
      items_count: order.items.count,       # N+1!
      total: order.items.sum(&:price)       # N+1 + N cálculos!
    }
  }
end

# ✅ Versão otimizada
def index
  @orders = Order
    .includes(:user, :items)
    .select("orders.*, COUNT(items.id) AS items_count_cache, SUM(items.price) AS total_cache")
    .joins(:items)
    .group("orders.id, users.id")
    .joins(:user)

  # Alternativa mais simples (2 queries ao invés de N+1)
  @orders = Order.includes(:user, :items)

  render json: @orders.map { |order|
    {
      id: order.id,
      user_name: order.user.name,
      items_count: order.items.size,        # usa cache do includes
      total: order.items.sum(&:price)       # em memória, sem query
    }
  }
end
```

---

## Problema 4: Sistema de Agrupamentos e Estatísticas

**Enunciado:** Endpoint `GET /api/v1/reports/sales` que retorna:
- Total vendido por mês (últimos 12 meses)
- Top 5 produtos mais vendidos
- Ticket médio por categoria

```ruby
class Api::V1::Reports::SalesController < ApplicationController
  def index
    render json: {
      monthly_sales: monthly_sales,
      top_products: top_products,
      avg_ticket_by_category: avg_ticket_by_category
    }
  end

  private

  def monthly_sales
    Order.confirmed
         .where("created_at >= ?", 12.months.ago)
         .group("DATE_TRUNC('month', created_at)")
         .order("DATE_TRUNC('month', created_at)")
         .sum(:total_price)
         .map { |month, total| { month: month.strftime("%Y-%m"), total: total.to_f } }
  end

  def top_products
    OrderItem
      .joins(:product)
      .joins(:order)
      .merge(Order.confirmed)
      .group("products.id", "products.name")
      .order("SUM(order_items.quantity) DESC")
      .limit(5)
      .sum("order_items.quantity")
      .map { |(id, name), qty| { product_id: id, name: name, quantity: qty } }
  end

  def avg_ticket_by_category
    Order.confirmed
         .joins(items: :product)
         .group("products.category")
         .average(:total_price)
         .map { |category, avg| { category: category, avg_ticket: avg.to_f.round(2) } }
  end
end
```

---

## Problema 5: Validações Complexas

**Enunciado:** Valide que:
- Email não pode pertencer a domínios banidos
- Senha deve ter letras, números e ao menos 8 chars
- Usuário não pode ter mais de 3 posts em 24h (rate limit)

```ruby
class User < ApplicationRecord
  BANNED_DOMAINS = %w[tempmail.com guerrillamail.com throwaway.email].freeze
  PASSWORD_REGEX = /\A(?=.*[a-zA-Z])(?=.*\d).{8,}\z/

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }
  validate :email_domain_not_banned
  validates :password, format: { with: PASSWORD_REGEX,
    message: "deve ter ao menos 8 caracteres com letras e números" },
    if: :password_required?

  private

  def email_domain_not_banned
    return unless email.present?
    domain = email.split("@").last.downcase
    errors.add(:email, "pertence a um domínio não permitido") if BANNED_DOMAINS.include?(domain)
  end

  def password_required?
    new_record? || password.present?
  end
end

class Post < ApplicationRecord
  belongs_to :user
  validate :rate_limit_check, on: :create

  private

  def rate_limit_check
    return unless user
    recent_count = user.posts.where("created_at > ?", 24.hours.ago).count
    if recent_count >= 3
      errors.add(:base, "Limite de 3 posts por 24 horas atingido")
    end
  end
end
```

---

## Problema 6: Otimizar uma Query / Resolver N+1

**Enunciado:** Escreva um teste para garantir que o endpoint não faz N+1.

```ruby
# spec/requests/api/v1/posts_spec.rb
RSpec.describe "GET /api/v1/posts", type: :request do
  before do
    users = create_list(:user, 5)
    users.each { |u| create_list(:post, 3, :published, user: u, tags: create_list(:tag, 2)) }
  end

  it "não faz N+1 queries" do
    # Aquece o cache de conexão com 1 request
    get "/api/v1/posts", headers: auth_headers(create(:user))

    expect {
      get "/api/v1/posts", headers: auth_headers(create(:user))
    }.to make_database_queries(count: 1..5)  # gem db-query-matchers
    # ou use: QueryCounter.count { get ... } == numero_esperado
  end
end
```

---

## Algoritmos Clássicos em Ruby

```ruby
# Busca binária
def busca_binaria(arr, alvo)
  esq, dir = 0, arr.length - 1
  while esq <= dir
    meio = (esq + dir) / 2
    if arr[meio] == alvo then return meio
    elsif arr[meio] < alvo then esq = meio + 1
    else dir = meio - 1
    end
  end
  -1
end

# FizzBuzz
(1..100).each do |n|
  if n % 15 == 0 then puts "FizzBuzz"
  elsif n % 3 == 0 then puts "Fizz"
  elsif n % 5 == 0 then puts "Buzz"
  else puts n
  end
end

# Agrupar anagramas
def agrupar_anagramas(palavras)
  palavras.group_by { |p| p.chars.sort.join }
end
# agrupar_anagramas(["eat","tea","tan","ate","nat","bat"])
# => {"aet"=>["eat","tea","ate"], "ant"=>["tan","nat"], "abt"=>["bat"]}

# Two Sum
def two_sum(nums, alvo)
  vistos = {}
  nums.each_with_index do |n, i|
    complemento = alvo - n
    return [vistos[complemento], i] if vistos.key?(complemento)
    vistos[n] = i
  end
end

# Fibonacci (memoizado)
def fib(n, memo = {})
  return n if n <= 1
  memo[n] ||= fib(n - 1, memo) + fib(n - 2, memo)
end

# Contar ocorrências de palavras
def contar_palavras(texto)
  texto.downcase.scan(/\w+/).tally
end
```
