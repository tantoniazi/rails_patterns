# 🧠 Módulo 14 – Arquitetura, Trade-offs e Code Review

---

## 1. Monolito Modular vs Microserviços

```
MONOLITO MODULAR (recomendado para começar)
  ✅ Deploy simples (1 app)
  ✅ Transações ACID cross-domain
  ✅ Sem latência de rede entre módulos
  ✅ Mais fácil de refatorar
  ❌ Escala tudo junto (não por módulo)
  ❌ Time inteiro precisa coordenar deploys

MICROSERVIÇOS
  ✅ Escala e deploy independente por serviço
  ✅ Times autônomos
  ✅ Isolamento de falhas
  ❌ Latência de rede entre serviços
  ❌ Transações distribuídas são complexas (saga pattern)
  ❌ Observabilidade mais difícil (tracing distribuído)

RESPOSTA PARA ENTREVISTA:
"Começaria com monolito modular bem estruturado.
Extrairia para microserviços apenas onde há:
1. Escala diferente (ex: serviço de vídeo vs API principal)
2. Time dedicado
3. Fronteira clara de domínio (DDD bounded context)
4. Tecnologia diferente justificada"
```

### Monolito Modular em Rails

```ruby
# Estrutura de engines Rails (módulos isolados)
# app/
#   modules/
#     billing/
#       app/models/billing/invoice.rb
#       app/controllers/billing/invoices_controller.rb
#       app/services/billing/charge_service.rb
#     inventory/
#       app/models/inventory/product.rb
#       app/controllers/inventory/products_controller.rb
#     notifications/
#       app/services/notifications/email_service.rb
#       app/jobs/notifications/send_email_job.rb

# Regras de dependência (enforçar com packwerk ou manual):
# billing → pode usar notifications
# billing → NÃO pode usar inventory diretamente (usa interface/event)
# inventory → NÃO pode usar billing

# Comunicação entre módulos via eventos (não acoplamento direto)
module Billing
  class ChargeService
    def call(order)
      charge!(order)
      # Publica evento – não conhece o módulo de notificações
      EventBus.publish("billing.charge_succeeded", order_id: order.id, amount: order.total)
    end
  end
end

module Notifications
  class EventSubscriber
    EventBus.subscribe("billing.charge_succeeded") do |payload|
      SendEmailJob.perform_later(payload[:order_id])
    end
  end
end
```

---

## 2. Architecture Decision Records (ADR)

```markdown
# ADR-001: Usar Sidekiq ao invés de DelayedJob

## Status
Aceito

## Contexto
Precisamos processar jobs assíncronos. Temos Redis disponível.
Volume esperado: 10.000 jobs/hora, picos de 1.000/min.

## Decisão
Usar Sidekiq com Redis.

## Consequências
✅ 10-50x mais rápido que DelayedJob (usa Redis vs PostgreSQL)
✅ Web UI incluída para monitoramento
✅ Retry automático com backoff exponencial
✅ Suporte a múltiplas filas com prioridade
❌ Adiciona dependência de Redis (já usamos, ok)
❌ At-least-once delivery (jobs precisam ser idempotentes)
❌ Dados de job perdidos se Redis reiniciar sem persistência

## Alternativas consideradas
- DelayedJob: mais simples, usa PostgreSQL (sem Redis), mais lento
- GoodJob: usa PostgreSQL, sem Redis, bom para apps menores
- Sidekiq Pro: $): features extras (reliable fetch, batches)
```

---

## 3. Code Review – Como Fazer e Receber

### Checklist para dar Code Review

```
FUNCIONALIDADE
  □ O código faz o que a issue descreve?
  □ Edge cases cobertos? (nil, vazio, usuário não autenticado)
  □ Erros tratados corretamente?

SEGURANÇA
  □ Tem SQL injection? (interpolação em queries)
  □ Strong Parameters cobrindo todos os campos?
  □ Autorização checada? (usuário pode fazer isso?)
  □ Dados sensíveis nos logs?

PERFORMANCE
  □ N+1 queries? (missing includes)
  □ Índice para as colunas filtradas?
  □ Operações pesadas no request (deveria ser job?)
  □ Cache onde faz sentido?

QUALIDADE
  □ Métodos com responsabilidade única?
  □ Nomes claros (sem abreviações obscuras)?
  □ Duplicação desnecessária?
  □ Complexidade ciclomática alta? (muitos ifs aninhados)

TESTES
  □ Casos felizes cobertos?
  □ Casos de erro cobertos?
  □ Testes testam comportamento, não implementação?
  □ Factories usam traits em vez de criar dados mágicos?
```

### Como dar feedback construtivo

```
❌ "Isso está errado"
✅ "Essa query pode ter N+1 – se chamarmos post.user dentro do loop,
    vai fazer 1 query por post. Que tal adicionar .includes(:user)?"

❌ "Por que você fez assim?"
✅ "Estou vendo que usou o callback after_create aqui.
    Alguma razão específica vs o Service Object?
    Callbacks costumam dificultar testes isolados."

❌ "Precisa de teste"
✅ "Faltou um teste para o caso onde o usuário não tem permissão.
    Acho que cover esse edge case é importante aqui porque..."

PREFIXOS ÚTEIS NO COMENTÁRIO:
[nit]:      Sugestão pequena, não bloqueante (estilo, nome)
[question]: Dúvida genuína, pode ser intencional
[blocker]:  Problema que precisa ser resolvido antes do merge
[praise]:   Boa solução! (dê feedback positivo também)
```

---

## 4. Explicar Trade-offs em Entrevistas

```
FRAMEWORK PARA RESPONDER QUALQUER TRADE-OFF:

"Eu escolheria X porque [benefício principal para o contexto dado].
 O custo é [desvantagem clara].
 Escolheria Y em vez se [condição específica]."

EXEMPLOS PRÁTICOS:

"SQL vs NoSQL para perfis de usuário?"
→ "SQL porque perfis têm schema estável e precisamos de integridade
   referencial (user → orders → payments). NoSQL faria sentido se
   o schema de perfil variasse muito por usuário, como campos customizados
   sem limite definido."

"Cache local vs Redis?"
→ "Cache local (memoization) para dados que só esse processo usa
   e mudam raramente. Redis quando múltiplos processos precisam
   compartilhar o cache. O custo do Redis é latência de rede (~1ms)
   e complexidade de invalidação."

"Sidekiq vs DelayedJob?"
→ "Sidekiq para volume alto – é 10-50x mais rápido por usar Redis
   ao invés do banco. O trade-off é adicionar Redis à infra.
   Para apps menores sem Redis, GoodJob ou DelayedJob são mais simples."

"Monolito vs microserviços?"
→ "Monolito para começar – deploy simples, transações ACID,
   sem latência entre serviços. Extrairia para microserviços
   apenas quando um domínio específico precisar de escala ou
   deploy independente, e quando houver time dedicado para isso."
```

---

## 5. Refatoração Progressiva

```ruby
# Antes: controller gordo, sem separação de responsabilidades
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.user = current_user
    @order.reference = "ORD-#{SecureRandom.hex(4).upcase}"
    @order.status = :pending

    if @order.save
      PaymentGateway.charge!(amount: @order.total, card: params[:card_token])
      @order.update!(status: :paid)
      OrderMailer.confirmation(@order).deliver_later
      Analytics.track(current_user, :order_placed, order_id: @order.id)
      render json: @order, status: :created
    else
      render json: { errors: @order.errors }, status: :unprocessable_entity
    end
  rescue PaymentGateway::Error => e
    @order&.update!(status: :payment_failed)
    render json: { error: e.message }, status: :payment_required
  end
end

# PASSO 1: Extrair para Service Object
class PlaceOrderService
  def initialize(user:, params:, card_token:)
    @user       = user
    @params     = params
    @card_token = card_token
  end

  def call
    order = build_order
    return failure(order.errors) unless order.save

    charge!(order)
    notify(order)
    success(order)
  rescue PaymentGateway::Error => e
    order&.update!(status: :payment_failed)
    failure(e.message)
  end

  private

  def build_order
    Order.new(@params).tap do |o|
      o.user      = @user
      o.reference = generate_reference
      o.status    = :pending
    end
  end

  def generate_reference
    "ORD-#{SecureRandom.hex(4).upcase}"
  end

  def charge!(order)
    PaymentGateway.charge!(amount: order.total, card: @card_token)
    order.update!(status: :paid)
  end

  def notify(order)
    OrderMailer.confirmation(order).deliver_later
    Analytics.track(@user, :order_placed, order_id: order.id)
  end

  def success(order) = OpenStruct.new(success?: true, order: order)
  def failure(error) = OpenStruct.new(success?: false, error: error)
end

# Controller limpo
class OrdersController < ApplicationController
  def create
    result = PlaceOrderService.new(
      user:       current_user,
      params:     order_params,
      card_token: params[:card_token]
    ).call

    if result.success?
      render json: result.order, status: :created
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end
end

# PASSO 2: Adicionar testes (mais fácil agora!)
RSpec.describe PlaceOrderService do
  subject(:service) { described_class.new(user: user, params: params, card_token: "tok_123") }

  let(:user)   { create(:user) }
  let(:params) { { items: [{ product_id: 1, qty: 2 }] } }

  context "quando pagamento funciona" do
    before { allow(PaymentGateway).to receive(:charge!).and_return(true) }

    it "cria o pedido como pago" do
      result = service.call
      expect(result).to be_success
      expect(result.order.status).to eq("paid")
    end
  end

  context "quando pagamento falha" do
    before { allow(PaymentGateway).to receive(:charge!).and_raise(PaymentGateway::Error) }

    it "marca pedido como payment_failed" do
      result = service.call
      expect(result).not_to be_success
    end
  end
end
```

---

## 6. Entrevista de Cultura Técnica – Perguntas Frequentes

```
"Me conta um problema difícil que você resolveu."
→ Use STAR: Situação, Tarefa, Ação, Resultado.
→ "Tínhamos um endpoint que levava 8s. Identifiquei N+1 com bullet,
    adicionei includes e um índice composto. Caiu para 120ms."

"Como você lida com dívida técnica?"
→ "Não deixo acumular sem visibilidade. Abro uma issue técnica,
    documento o problema e o custo de não resolver.
    Negoço com produto: 20% do sprint para melhorias técnicas.
    Prefiro refatorar incrementalmente do que reescrever."

"Como você garante qualidade em um time?"
→ "Code review com checklist, testes como gate de CI,
    linting automático (RuboCop), pair programming em áreas complexas,
    e post-mortems sem culpa quando algo vai para produção errado."

"Quando você quebraria uma regra técnica?"
→ "Com urgência de negócio justificada e dívida técnica documentada.
    Por exemplo: quick fix direto no banco para incidente em produção,
    com issue criada para fazer o fix correto em 48h."
```
