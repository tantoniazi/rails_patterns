# 🔒 Módulo 8 – Segurança em Rails

> Segurança é o tópico que mais diferencia sênior de pleno. Entrevistadores esperam que você identifique vulnerabilidades antes de serem exploradas.

---

## 1. SQL Injection

```ruby
# ❌ VULNERÁVEL – interpolação direta
User.where("email = '#{params[:email]}'")
User.where("name LIKE '%#{params[:q]}%'")

# ✅ SEGURO – placeholders (sanitiza automaticamente)
User.where("email = ?", params[:email])
User.where("name LIKE ?", "%#{params[:q]}%")
User.where(email: params[:email])
User.where("age > :min AND age < :max", min: 18, max: 65)

# Atenção: order() NÃO sanitiza!
# ❌ Vulnerável
User.order(params[:sort])

# ✅ Whitelist explícita
ALLOWED_SORTS = %w[name email created_at].freeze
sort = ALLOWED_SORTS.include?(params[:sort]) ? params[:sort] : "created_at"
User.order(sort)
```

---

## 2. Cross-Site Scripting (XSS)

```ruby
# Rails escapa HTML por padrão em ERB com <%= %>
# ❌ PERIGOSO – desabilita o escape
<%= raw user.bio %>
<%= user.bio.html_safe %>

# ✅ SEGURO – escape automático
<%= user.bio %>

# Quando precisar renderizar HTML confiável (ex: editor WYSIWYG):
# Use sanitize com allowlist
<%= sanitize user.bio, tags: %w[p b i a ul li], attributes: %w[href] %>

# Em JSON responses (APIs): não há risco de XSS direto,
# mas o Content-Type header deve ser application/json
render json: { name: user.name }  # correto

# Content Security Policy (CSP) – linha de defesa adicional
# config/initializers/content_security_policy.rb
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src  :self
  policy.style_src   :self, :unsafe_inline
  policy.img_src     :self, :data, "https://cdn.meusite.com"
  policy.connect_src :self
  policy.font_src    :self
end
```

---

## 3. CSRF (Cross-Site Request Forgery)

```ruby
# Rails inclui proteção CSRF por padrão em controllers HTML
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception  # padrão
end

# Para APIs JSON (token-based auth), desabilite para API controllers
class ApiController < ActionController::API
  # ActionController::API não inclui CSRF por padrão
  # Mas valide o token JWT em todos os requests
end

# Token CSRF nas views
# Rails insere automaticamente em forms com form_with / form_tag
<%= form_with url: posts_path do |f| %>
  # inclui automaticamente: <input type="hidden" name="authenticity_token" ...>
<% end %>

# Para requests AJAX (JS)
const token = document.querySelector('meta[name="csrf-token"]').content;
fetch('/posts', {
  method: 'POST',
  headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ post: { title: 'Teste' } })
});
```

---

## 4. Mass Assignment Protection

```ruby
# ❌ PERIGOSO – aceita qualquer parâmetro
User.create(params[:user])
user.update(params[:user])

# ✅ SEGURO – Strong Parameters (whitelist explícita)
def user_params
  params.require(:user).permit(:name, :email, :password)
  # NÃO inclua: :role, :admin, :balance – usuário não pode setar isso!
end

# Campos sensíveis que NUNCA devem estar em permit():
# :role, :admin, :is_admin, :balance, :credits, :confirmed_at, :locked_at

# Para admins (contexto diferente, permit diferente)
def admin_user_params
  params.require(:user).permit(:name, :email, :role, :active)
end
```

---

## 5. Autorização (não confunda com autenticação)

```ruby
# Autenticação = quem é você? (Devise, JWT)
# Autorização  = o que você pode fazer? (Pundit, CanCanCan)

# Com Pundit
# app/policies/post_policy.rb
class PostPolicy < ApplicationPolicy
  def show?
    true  # qualquer um pode ver
  end

  def update?
    user.admin? || record.user_id == user.id
  end

  def destroy?
    user.admin? || record.user_id == user.id
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user_id: user.id).or(scope.published)
      end
    end
  end
end

# No controller
class PostsController < ApplicationController
  def update
    @post = Post.find(params[:id])
    authorize @post             # lança Pundit::NotAuthorizedError se não puder
    @post.update!(post_params)
    render json: @post
  end

  def index
    @posts = policy_scope(Post)  # aplica o Scope automaticamente
    render json: @posts
  end
end

# Tratar o erro globalmente
class ApplicationController < ActionController::API
  rescue_from Pundit::NotAuthorizedError do
    render json: { error: "Acesso negado" }, status: :forbidden
  end
end
```

---

## 6. Rate Limiting

```ruby
# Gem: rack-attack
# gem 'rack-attack'

# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle: máximo 5 logins por minuto por IP
  throttle("logins/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/sessions" && req.post?
  end

  # Throttle: máximo 100 requests por minuto por usuário autenticado
  throttle("api/user", limit: 100, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.path.start_with?("/api/")
  end

  # Blocklist: IPs na lista negra
  blocklist("block bad ips") do |req|
    BlockedIp.exists?(ip: req.ip)
  end

  # Safelist: IPs internos nunca são bloqueados
  safelist("allow from localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  # Resposta customizada quando bloqueado
  self.throttled_responder = lambda do |env|
    [429, { "Content-Type" => "application/json" },
     [{ error: "Muitas requisições. Tente novamente em breve." }.to_json]]
  end
end

# config/application.rb
config.middleware.use Rack::Attack
```

---

## 7. Sensitive Data Exposure

```ruby
# Nunca logar senhas, tokens ou cartões
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :password_confirmation,
  :credit_card, :cvv, :token, :secret,
  :api_key, :access_token, :refresh_token
]

# Nunca expor campos sensíveis em JSON
class UserSerializer
  def initialize(user)
    @user = user
  end

  def as_json
    {
      id:         @user.id,
      name:       @user.name,
      email:      @user.email,
      created_at: @user.created_at
      # NÃO inclua: password_digest, reset_password_token, etc.
    }
  end
end

# Armazenar secrets com Rails credentials (nunca em código)
# config/credentials.yml.enc (encriptado)
# Acessar: Rails.application.credentials.stripe[:secret_key]

# Variáveis de ambiente para 12-factor apps
stripe_key = ENV.fetch("STRIPE_SECRET_KEY") { raise "STRIPE_SECRET_KEY não definida!" }

# Bcrypt para senhas (já usado pelo Devise)
# Nunca armazene senhas em plain text ou MD5/SHA1
BCrypt::Password.create("minha_senha")           # hash
BCrypt::Password.new(hash).is_password?("senha") # verificar
```

---

## 8. Direct Object Reference (IDOR)

```ruby
# ❌ VULNERÁVEL – usuário pode acessar qualquer registro trocando o ID
def show
  @invoice = Invoice.find(params[:id])   # qualquer invoice!
  render json: @invoice
end

# ✅ SEGURO – sempre escopar pelo usuário atual
def show
  @invoice = current_user.invoices.find(params[:id])
  # ActiveRecord::RecordNotFound se não pertencer ao usuário
  render json: @invoice
end

# Ou via Pundit (authorize verifica a policy)
def show
  @invoice = Invoice.find(params[:id])
  authorize @invoice
  render json: @invoice
end
```

---

## 9. Dependency Security

```bash
# Verificar vulnerabilidades nas gems
bundle audit check --update

# Atualizar gems com patches de segurança
bundle update --conservative

# GitHub Dependabot (no repo) – abre PRs automáticos para updates

# Verificar o código em busca de más práticas
gem install brakeman
brakeman -A   # analisa o app Rails inteiro
# Gera relatório com: SQL injection, XSS, mass assignment, etc.
```

---

## 10. Checklist de Segurança

```
AUTENTICAÇÃO
  ☐ Senhas com bcrypt (mín. custo 12)
  ☐ Lockout após N tentativas falhas (Devise :lockable)
  ☐ Reset de senha com token expirado (< 2h)
  ☐ 2FA para contas privilegiadas

AUTORIZAÇÃO
  ☐ Policy para cada ação sensível (Pundit)
  ☐ Scope filtra registros por usuário
  ☐ Admin routes protegidas separadamente

INPUTS
  ☐ Strong Parameters em todos os controllers
  ☐ Placeholders em toda query SQL
  ☐ Whitelist em order(), sort, direction
  ☐ sanitize() em campos HTML do usuário

OUTPUTS
  ☐ Content-Type correto em todas responses
  ☐ Campos sensíveis fora do JSON
  ☐ Filter Parameters configurado

INFRA
  ☐ HTTPS obrigatório (force_ssl)
  ☐ Secure + HttpOnly cookies
  ☐ CORS configurado (rack-cors)
  ☐ Rate limiting (rack-attack)
  ☐ Headers de segurança (SecureHeaders gem)
  ☐ brakeman no CI pipeline
```
