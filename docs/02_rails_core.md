# 🛤️ Módulo 2 – Ruby on Rails Core

## 1. MVC e Convenções

```
app/
  models/        → regras de negócio, validações, associações
  controllers/   → orquestração de request/response
  views/         → apresentação (ERB/JSON)
config/
  routes.rb      → mapeamento URL → controller#action
db/
  migrate/       → versionamento do banco
  schema.rb      → estado atual do banco
```

**Convenção sobre Configuração:**
- Model `Post` → tabela `posts`
- Controller `PostsController` → `app/controllers/posts_controller.rb`
- Views em `app/views/posts/`
- Helper em `app/helpers/posts_helper.rb`

---

## 2. Routing

```ruby
# config/routes.rb

Rails.application.routes.draw do
  # RESTful completo (7 ações)
  resources :posts

  # Somente algumas ações
  resources :comments, only: [:index, :create, :destroy]

  # Aninhado
  resources :posts do
    resources :comments, only: [:create, :destroy]
    member do
      post :publish      # POST /posts/:id/publish
    end
    collection do
      get :trending      # GET /posts/trending
    end
  end

  # Namespace (admin)
  namespace :api do
    namespace :v1 do
      resources :users
    end
  end

  # Rota customizada
  get "/login",  to: "sessions#new",     as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  root "home#index"
end
```

```bash
# Ver todas as rotas
rails routes
rails routes | grep post
```

---

## 3. Controllers – Actions e Filtros

```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post, only: [:show, :update, :destroy]
  after_action  :log_access, only: [:show]

  # GET /posts
  def index
    @posts = Post.published.page(params[:page]).per(20)
    render json: @posts
  end

  # GET /posts/:id
  def show
    render json: @post
  end

  # POST /posts
  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      render json: @post, status: :created
    else
      render json: { errors: @post.errors }, status: :unprocessable_entity
    end
  end

  # PATCH /posts/:id
  def update
    if @post.update(post_params)
      render json: @post
    else
      render json: { errors: @post.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /posts/:id
  def destroy
    @post.destroy
    head :no_content
  end

  private

  def set_post
    @post = Post.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Post não encontrado" }, status: :not_found
  end

  def post_params
    params.require(:post).permit(:title, :body, :status, tag_ids: [])
  end

  def log_access
    Rails.logger.info "Post #{@post.id} acessado por #{current_user.id}"
  end
end
```

---

## 4. ActiveRecord – O Coração do Rails

### Associações

```ruby
class User < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :comments, through: :posts
  has_one  :profile, dependent: :destroy
  has_many :favorites
  has_many :favorited_posts, through: :favorites, source: :post

  belongs_to :company, optional: true
end

class Post < ApplicationRecord
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :tags, through: :post_tags
  has_one_attached :cover_image   # Active Storage
end

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :commentable, polymorphic: true  # polimórfico
end
```

### Validações

```ruby
class User < ApplicationRecord
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :name,  presence: true, length: { minimum: 2, maximum: 100 }
  validates :age,   numericality: { greater_than: 0 }, allow_nil: true

  validate :email_nao_pode_ser_blacklisted

  private

  def email_nao_pode_ser_blacklisted
    if EmailBlacklist.include?(email)
      errors.add(:email, "está na lista negra")
    end
  end
end
```

### Callbacks

```ruby
class Order < ApplicationRecord
  before_validation :normalize_status
  before_create     :set_reference_number
  after_create      :send_confirmation_email
  before_destroy    :check_can_destroy

  # Ordem dos callbacks:
  # before_validation → after_validation
  # before_save → before_create/update → after_create/update → after_save
  # before_destroy → after_destroy

  private

  def normalize_status
    self.status = status.to_s.downcase.strip
  end

  def set_reference_number
    self.reference = "ORD-#{SecureRandom.hex(4).upcase}"
  end

  def send_confirmation_email
    OrderMailer.confirmation(self).deliver_later
  end

  def check_can_destroy
    throw(:abort) if status == "shipped"
  end
end
```

### Scopes

```ruby
class Post < ApplicationRecord
  scope :published,    -> { where(status: :published) }
  scope :draft,        -> { where(status: :draft) }
  scope :recent,       -> { order(created_at: :desc) }
  scope :by_author,    ->(user_id) { where(user_id: user_id) }
  scope :with_comments, -> { includes(:comments) }
  scope :popular,      -> { where("views_count > ?", 1000) }

  # Encadeável: Post.published.recent.by_author(1).limit(10)
end
```

### Queries Avançadas

```ruby
# Básico
User.all
User.find(1)
User.find_by(email: "a@b.com")
User.where(active: true)
User.where("age > ?", 18)              # evitar interpolação direta!
User.where(age: 18..30)               # range
User.where.not(status: :banned)

# Ordenação, limite, offset
User.order(:name).limit(10).offset(20)

# Seleção de colunas
User.select(:id, :name, :email)

# Joins
Post.joins(:user).where(users: { active: true })
Post.joins(:comments).group("posts.id").having("COUNT(comments.id) > 5")

# Includes (evita N+1)
Post.includes(:user, :comments, :tags)
Post.eager_load(:user)   # força LEFT OUTER JOIN
Post.preload(:comments)  # query separada

# Aggregate
User.count
User.sum(:balance)
User.average(:age)
User.maximum(:created_at)
User.group(:status).count

# find_each (processa em lotes, evita carregar tudo na memória)
User.find_each(batch_size: 500) do |user|
  user.send_newsletter!
end

# update_all, delete_all (sem callbacks!)
User.where(confirmed: false).update_all(active: false)
Post.where("created_at < ?", 1.year.ago).delete_all
```

---

## 5. Migrations

```ruby
# rails g migration CreatePosts title:string body:text user:references status:integer
class CreatePosts < ActiveRecord::Migration[7.1]
  def change
    create_table :posts do |t|
      t.string     :title,  null: false
      t.text       :body
      t.references :user,   null: false, foreign_key: true
      t.integer    :status, default: 0, null: false
      t.string     :slug,   index: { unique: true }

      t.timestamps
    end

    add_index :posts, [:status, :created_at]  # índice composto
  end
end

# Adicionar coluna
class AddViewsCountToPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :posts, :views_count, :integer, default: 0, null: false
    add_index  :posts, :views_count
  end
end

# Renomear, remover
class RefactorUsers < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :username, :handle
    remove_column :users, :legacy_field, :string
    change_column_null :users, :email, false
  end
end
```

---

## 6. Strong Parameters

```ruby
# Permitir apenas parâmetros esperados (proteção contra mass assignment)
def user_params
  params.require(:user).permit(
    :name, :email, :password, :password_confirmation,
    :avatar,
    address_attributes: [:street, :city, :zip, :_destroy],
    role_ids: []
  )
end
```

---

## 7. Helpers e Views (ERB)

```erb
<%# app/views/posts/index.html.erb %>
<%= link_to "Novo Post", new_post_path, class: "btn btn-primary" %>

<% @posts.each do |post| %>
  <article>
    <h2><%= post.title %></h2>
    <p><%= truncate(post.body, length: 200) %></p>
    <%= link_to "Ler mais", post_path(post) %>
  </article>
<% end %>

<%= paginate @posts %>
```

```ruby
# app/helpers/posts_helper.rb
module PostsHelper
  def status_badge(post)
    css = post.published? ? "badge-success" : "badge-warning"
    content_tag(:span, post.status.humanize, class: "badge #{css}")
  end
end
```
