# 🔌 Módulo 13 – GraphQL, WebSockets, Active Storage e Multi-tenancy

---

## 1. GraphQL com graphql-ruby

```ruby
# gem 'graphql'
# rails g graphql:install

# app/graphql/types/user_type.rb
module Types
  class UserType < Types::BaseObject
    field :id,         ID,      null: false
    field :name,       String,  null: false
    field :email,      String,  null: false
    field :posts,      [Types::PostType], null: false
    field :post_count, Integer, null: false

    def post_count
      object.posts.published.count
    end
  end
end

# app/graphql/types/post_type.rb
module Types
  class PostType < Types::BaseObject
    field :id,         ID,     null: false
    field :title,      String, null: false
    field :body,       String, null: true
    field :status,     String, null: false
    field :author,     Types::UserType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def author
      # Sem dataloader = N+1 query!
      object.user
    end
  end
end

# app/graphql/types/query_type.rb
module Types
  class QueryType < Types::BaseObject
    field :posts, [Types::PostType], null: false do
      argument :status, String, required: false
      argument :limit,  Integer, required: false, default_value: 20
    end

    field :post, Types::PostType, null: true do
      argument :id, ID, required: true
    end

    field :user, Types::UserType, null: true do
      argument :id, ID, required: true
    end

    def posts(status: nil, limit:)
      scope = Post.includes(:user)
      scope = scope.where(status: status) if status
      scope.limit(limit)
    end

    def post(id:)
      Post.find_by(id: id)
    end

    def user(id:)
      User.find_by(id: id)
    end
  end
end

# Mutation
module Mutations
  class CreatePost < BaseMutation
    argument :title,  String, required: true
    argument :body,   String, required: true
    argument :status, String, required: false, default_value: "draft"

    field :post,   Types::PostType, null: true
    field :errors, [String],        null: false

    def resolve(title:, body:, status:)
      post = context[:current_user].posts.build(title: title, body: body, status: status)
      if post.save
        { post: post, errors: [] }
      else
        { post: nil, errors: post.errors.full_messages }
      end
    end
  end
end
```

### N+1 em GraphQL – Dataloader

```ruby
# sem dataloader: N+1 ao resolver posts com authors
# COM dataloader: batch de queries

# app/graphql/loaders/record_loader.rb
class RecordLoader < GraphQL::Batch::Loader
  def initialize(model, column: :id)
    @model  = model
    @column = column
  end

  def perform(ids)
    @model.where(@column => ids).each do |record|
      fulfill(record.public_send(@column), record)
    end
    ids.each { |id| fulfill(id, nil) unless fulfilled?(id) }
  end
end

# No PostType:
def author
  RecordLoader.for(User).load(object.user_id)
  # Agrupa TODOS os user_id da query e faz 1 só SELECT
end

# Exemplo de query GraphQL
# POST /graphql
# {
#   posts(status: "published", limit: 10) {
#     id
#     title
#     author { name email }
#   }
# }
```

---

## 2. WebSockets com Action Cable

```ruby
# config/cable.yml
development:
  adapter: redis
  url: redis://localhost:6379

production:
  adapter: redis
  url: <%= ENV["REDIS_URL"] %>

# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token] || request.headers["Authorization"]&.split(" ")&.last
      payload = JwtService.decode(token)
      User.find(payload[:user_id])
    rescue
      reject_unauthorized_connection
    end
  end
end

# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    @room = Room.find(params[:room_id])
    stream_for @room   # stream_for usa o modelo como chave
  end

  def unsubscribed
    stop_all_streams
  end

  def receive(data)
    message = @room.messages.create!(
      content: data["content"],
      user:    current_user
    )
    # Broadcast para TODOS conectados nessa sala
    ChatChannel.broadcast_to(@room, {
      id:      message.id,
      content: message.content,
      user:    { id: current_user.id, name: current_user.name },
      sent_at: message.created_at.iso8601
    })
  end
end

# Broadcast de fora do channel (ex: de um job)
ChatChannel.broadcast_to(room, { content: "Sistema: sala atualizada" })
ActionCable.server.broadcast("notifications:#{user.id}", { type: "alert", msg: "Novo pedido!" })

# No JavaScript
const cable = ActionCable.createConsumer("wss://app.com/cable?token=JWT_TOKEN")

const chat = cable.subscriptions.create(
  { channel: "ChatChannel", room_id: 42 },
  {
    connected() { console.log("Conectado!") },
    received(data) { renderMessage(data) },
    send(content) { this.perform("receive", { content }) }
  }
)
```

### Hotwire (Turbo Streams) – WebSocket sem escrever JS

```ruby
# app/controllers/messages_controller.rb
def create
  @message = @room.messages.create!(message_params.merge(user: current_user))

  respond_to do |format|
    format.turbo_stream  # broadcasts automaticamente
    format.json { render json: @message }
  end
end

# app/views/messages/create.turbo_stream.erb
<%= turbo_stream.append "messages", @message %>
<%= turbo_stream.update "message-form", partial: "form" %>

# app/models/message.rb – broadcast declarativo
class Message < ApplicationRecord
  belongs_to :room
  belongs_to :user

  after_create_commit :broadcast_to_room

  private
  def broadcast_to_room
    broadcast_append_to room, target: "messages"
  end
end
```

---

## 3. Active Storage

```ruby
# config/storage.yml
amazon:
  service: S3
  access_key_id:     <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
  region: us-east-1
  bucket: meu-bucket-producao

# config/environments/production.rb
config.active_storage.service = :amazon

# No model
class User < ApplicationRecord
  has_one_attached  :avatar
  has_many_attached :documents
end

class Post < ApplicationRecord
  has_one_attached :cover_image do |attachable|
    attachable.variant :thumbnail, resize_to_limit: [300, 300]
    attachable.variant :medium,    resize_to_limit: [800, 600]
  end
end

# No controller
def update
  current_user.update!(user_params)
end

def user_params
  params.require(:user).permit(:name, :avatar)
end

# Na view
image_tag current_user.avatar if current_user.avatar.attached?
image_tag post.cover_image.variant(:thumbnail)

# URLs
url_for(user.avatar)                              # URL gerada
rails_blob_url(user.avatar, disposition: "inline") # URL com opções
user.avatar.url(expires_in: 1.hour)               # URL temporária para S3

# Direct Upload (do browser direto para S3, sem passar pelo servidor)
# javascript_include_tag "@rails/activestorage"
# app/javascript/application.js
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

# No form
<%= form.file_field :avatar, direct_upload: true %>

# Processamento em background (recomendado para produção)
# config/environments/production.rb
config.active_storage.variant_processor = :vips   # mais rápido que ImageMagick

# Validações (Active Storage não tem validações nativas)
# gem 'active_storage_validations'
class User < ApplicationRecord
  has_one_attached :avatar

  validates :avatar,
    content_type: ["image/png", "image/jpeg", "image/webp"],
    size: { less_than: 5.megabytes, message: "deve ser menor que 5MB" }
end
```

---

## 4. Multi-tenancy

```ruby
# ESTRATÉGIA 1: Row-level (coluna tenant_id em todas as tabelas)
# Mais simples, single DB, mas risco de vazamento de dados

# gem 'acts_as_tenant'
class ApplicationController < ActionController::Base
  before_action :set_tenant

  private
  def set_tenant
    current_tenant = Company.find_by!(subdomain: request.subdomain)
    ActsAsTenant.set_tenant(current_tenant)
  end
end

class Post < ApplicationRecord
  acts_as_tenant :company
  # Adiciona company_id e escopа TODAS as queries automaticamente
end

# Post.all → SELECT * FROM posts WHERE company_id = ?
# Post.create!(title: "X") → insere com company_id do tenant atual

# ESTRATÉGIA 2: Schema por tenant (PostgreSQL schemas)
# Isolamento real, mas mais complexo de gerenciar

# gem 'apartment'
# config/initializers/apartment.rb
Apartment.configure do |config|
  config.tenant_names = -> { Company.pluck(:subdomain) }
  config.excluded_models = %w[Company User]  # tabelas globais
end

# Criar tenant
Apartment::Tenant.create("empresa_abc")

# Mudar de tenant
Apartment::Tenant.switch("empresa_abc") do
  Post.all   # SELECT * FROM empresa_abc.posts
end

# No middleware (automático por subdomain)
# config/initializers/apartment.rb
config.middleware_excluded_paths = ["/health", "/api/v1/auth"]

# ESTRATÉGIA 3: Database por tenant
# Máximo isolamento, mas operacionalmente caro
# Usado em: healthcare, finance (regulação exige isolamento)
class TenantDatabase
  def self.switch(tenant)
    ActiveRecord::Base.establish_connection(
      adapter:  "postgresql",
      host:     ENV["DB_HOST"],
      database: "tenant_#{tenant.subdomain}",
      username: ENV["DB_USERNAME"],
      password: ENV["DB_PASSWORD"]
    )
    yield
  ensure
    ActiveRecord::Base.establish_connection(:primary)
  end
end

# TRADE-OFFS
# Row-level:   fácil de implementar, risco de bug expor dados entre tenants
# Schema:      bom isolamento, migrations mais complexas (1 schema/tenant)
# DB:          isolamento máximo, custo operacional alto, backups separados
```

---

## 5. Perguntas de Entrevista – Estes Tópicos

```
GRAPHQL
Q: Por que usar GraphQL vs REST?
A: Cliente especifica exatamente os dados que quer (sem over/under-fetching),
   uma única URL, schema como contrato, introspection. Contra: complexidade,
   caching HTTP mais difícil, n+1 é perigoso sem dataloader.

Q: Como resolver N+1 em GraphQL?
A: graphql-batch (Dataloader): agrupa todos os IDs de uma query, resolve em 1 SQL.

WEBSOCKETS
Q: Quando usar WebSocket vs Polling vs SSE?
A: WebSocket: bidirecional em tempo real (chat, jogos, colaboração)
   SSE: unidirecional servidor→cliente (notificações, feeds)
   Polling: quando simplicidade > eficiência (relatórios, dashboards lentos)

MULTI-TENANCY
Q: Qual estratégia de multi-tenancy você escolheria?
A: Depende do nível de isolamento exigido. SaaS comum: row-level (mais simples,
   escala melhor). Regulado (HIPAA, PCI): schema ou DB separado.
   O risco do row-level é um bug de segurança expor dados entre tenants.
```
