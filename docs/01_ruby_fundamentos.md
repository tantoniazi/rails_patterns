# 💎 Módulo 1 – Ruby Fundamentos

## 1. Tipos, Variáveis e Escopo

```ruby
# Tipos básicos
nome   = "Rails"          # String
versao = 7.1              # Float
ano    = 2024             # Integer
ativo  = true             # Boolean
nada   = nil              # NilClass

# Símbolos (imutáveis, internados na memória – use como chaves de hash)
:status
:email

# Escopo de variáveis
local_var   = "só aqui"
@instancia  = "dentro da classe"
@@classe    = "compartilhada entre instâncias"
$global     = "evite!"
CONSTANTE   = "MAIÚSCULO"
```

## 2. Arrays, Hashes e Enums

```ruby
# Arrays
frutas = ["maçã", "banana", "laranja"]
frutas.push("uva")           # adiciona no fim
frutas.unshift("morango")    # adiciona no início
frutas.map { |f| f.upcase }  # ["MAÇÃ", "BANANA", ...]
frutas.select { |f| f.length > 5 }
frutas.reject { |f| f.start_with?("m") }
frutas.reduce("") { |acc, f| acc + f }

# Hashes
usuario = { nome: "Ana", email: "ana@mail.com", idade: 30 }
usuario[:nome]              # "Ana"
usuario.fetch(:cpf, "N/A") # "N/A" (default seguro)
usuario.merge(admin: false)
usuario.select { |k, v| k == :nome }
usuario.map { |k, v| [k, v.to_s] }.to_h

# Enum no Rails (campo inteiro mapeado para símbolos)
class Pedido < ApplicationRecord
  enum status: { pendente: 0, aprovado: 1, cancelado: 2 }
end
# Uso: pedido.aprovado!  pedido.aprovado?  Pedido.aprovado
```

## 3. Iteradores, Blocos e Lambdas

```ruby
# each vs map vs select vs reduce
[1, 2, 3].each   { |n| puts n }           # efeito colateral
[1, 2, 3].map    { |n| n * 2 }            # [2, 4, 6]
[1, 2, 3].select { |n| n.odd? }           # [1, 3]
[1, 2, 3].reduce(0) { |soma, n| soma + n } # 6

# Blocos (Proc implícito)
def executar
  puts "antes"
  yield if block_given?
  puts "depois"
end
executar { puts "dentro do bloco" }

# Proc vs Lambda
meu_proc   = Proc.new { |x| x * 2 }
minha_lambda = lambda { |x| x * 2 }
arrow_lambda = ->(x) { x * 2 }

# Diferença chave:
# Lambda verifica aridade e tem return local
# Proc não verifica aridade e return sai do método pai
```

## 4. Módulos e Mixins

```ruby
module Auditavel
  def criado_por
    "Sistema"
  end

  def log_acao(acao)
    puts "[#{Time.now}] #{acao} executada"
  end
end

module Exportavel
  def to_csv
    instance_variables.map { |v| instance_variable_get(v) }.join(",")
  end
end

class Produto
  include Auditavel    # adiciona métodos de instância
  include Exportavel
  extend  Auditavel    # adiciona como métodos de classe (extend)

  attr_accessor :nome, :preco

  def initialize(nome, preco)
    @nome  = nome
    @preco = preco
  end
end

p = Produto.new("Caneta", 2.5)
p.criado_por  # "Sistema"
p.to_csv      # "Caneta,2.5"
```

## 5. Exceções

```ruby
def dividir(a, b)
  raise ArgumentError, "Divisor não pode ser zero" if b.zero?
  a / b
rescue ArgumentError => e
  puts "Erro de argumento: #{e.message}"
  nil
rescue ZeroDivisionError => e
  puts "Divisão por zero: #{e.message}"
  nil
ensure
  puts "Sempre executa (fechar conexões, etc.)"
end

# Exceção customizada
class SaldoInsuficienteError < StandardError
  def initialize(saldo, valor)
    super("Saldo #{saldo} insuficiente para saque de #{valor}")
  end
end
```

## 6. Metaprogramação (Conceitos Básicos)

```ruby
# method_missing – intercepta chamadas a métodos inexistentes
class FlexibleHash
  def initialize
    @dados = {}
  end

  def method_missing(nome, *args)
    chave = nome.to_s.chomp("=").to_sym
    if nome.to_s.end_with?("=")
      @dados[chave] = args.first
    else
      @dados[chave]
    end
  end

  def respond_to_missing?(nome, include_private = false)
    true
  end
end

fh = FlexibleHash.new
fh.nome = "Rails"
fh.nome  # "Rails"

# define_method – cria métodos dinamicamente
class Relatorio
  %w[pdf csv xlsx].each do |formato|
    define_method("exportar_#{formato}") do
      puts "Exportando como #{formato.upcase}"
    end
  end
end

r = Relatorio.new
r.exportar_pdf   # "Exportando como PDF"
r.exportar_csv   # "Exportando como CSV"

# send – chama método pelo nome (string/símbolo)
"hello".send(:upcase)          # "HELLO"
objeto.send(:metodo_privado)   # acessa privados também!

# attr_accessor por baixo dos panos
class MinhaClasse
  def self.meu_attr(nome)
    define_method(nome) { instance_variable_get("@#{nome}") }
    define_method("#{nome}=") { |v| instance_variable_set("@#{nome}", v) }
  end

  meu_attr :titulo
end
```

## 7. Enumerable Methods – Os mais cobrados

```ruby
nums = [3, 1, 4, 1, 5, 9, 2, 6]

nums.sort                          # [1, 1, 2, 3, 4, 5, 6, 9]
nums.sort_by { |n| -n }            # decrescente
nums.min / nums.max
nums.minmax                        # [1, 9]
nums.sum                           # 31
nums.count { |n| n > 3 }          # 4
nums.any? { |n| n > 8 }           # true
nums.all? { |n| n > 0 }           # true
nums.none? { |n| n > 10 }         # true
nums.flat_map { |n| [n, n * 2] }  # achata um nível
nums.each_with_object([]) { |n, arr| arr << n * 3 }
nums.each_slice(3).to_a            # [[3,1,4],[1,5,9],[2,6]]
nums.each_cons(3).to_a             # janelas deslizantes de 3
nums.zip([10, 20, 30])             # [[3,10],[1,20],[4,30],...]
nums.tally                         # {3=>1, 1=>2, 4=>1, ...}
nums.uniq                          # remove duplicatas
nums.group_by { |n| n.even? ? :par : :impar }
nums.flat_map.with_index { |n, i| [i, n] }
```

## 8. Comparable e Comparable Module

```ruby
class Produto
  include Comparable   # ganha: >, <, >=, <=, between?, clamp

  attr_accessor :preco

  def initialize(nome, preco)
    @nome  = nome
    @preco = preco
  end

  def <=>(outro)   # único método obrigatório
    @preco <=> outro.preco
  end
end

a = Produto.new("Caneta", 2.0)
b = Produto.new("Livro",  35.0)
c = Produto.new("Mochila", 89.0)

a < b            # true
[c, a, b].sort   # [a, b, c] — ordenados pelo preço
[c, a, b].min    # a (caneta)
b.between?(a, c) # true
```

## 9. Frozen Objects e Imutabilidade

```ruby
# freeze – torna objeto imutável (evita bugs sutis)
CONFIG = { max_retries: 3, timeout: 30 }.freeze
CONFIG[:max_retries] = 5   # FrozenError!

# String literals frozen por padrão no Ruby 3+
# magic comment no topo dos arquivos Rails:
# frozen_string_literal: true

str = "hello".freeze
str << " world"   # FrozenError!
str + " world"    # OK! – cria nova string

# dup vs clone
original = "texto".freeze
original.dup.frozen?    # false – dup ignora frozen
original.clone.frozen?  # true  – clone preserva frozen
```

## 10. Concorrência: Threads, Fibers e Ractors

```ruby
# Thread – execução paralela (cuidado com GIL no MRI Ruby)
threads = (1..5).map do |i|
  Thread.new do
    sleep(rand * 0.1)
    puts "Thread #{i} concluída"
  end
end
threads.each(&:join)   # aguarda todas terminarem

# Mutex – evita race conditions
mutex = Mutex.new
contador = 0

10.times.map do
  Thread.new do
    mutex.synchronize { contador += 1 }
  end
end.each(&:join)
puts contador   # sempre 10 (sem mutex poderia ser < 10)

# Fiber – concorrência cooperativa (leve, sem preempção)
fib = Fiber.new do
  a, b = 0, 1
  loop do
    Fiber.yield a
    a, b = b, a + b
  end
end

10.times { print "#{fib.resume} " }
# 0 1 1 2 3 5 8 13 21 34

# Enumerator::Lazy – processa sequências infinitas
naturais = (1..Float::INFINITY).lazy
primeiros_pares = naturais.select(&:even?).first(5)
# [2, 4, 6, 8, 10] – sem processar o infinito todo
```

## 11. Pattern Matching (Ruby 3+)

```ruby
# case/in – mais poderoso que case/when
usuario = { nome: "Ana", role: "admin", idade: 30 }

case usuario
in { role: "admin", nome: String => nome }
  puts "Admin: #{nome}"
in { role: "member", idade: (18..) }
  puts "Membro adulto"
in { role: "guest" }
  puts "Visitante"
end

# Deconstruct em arrays
case [1, 2, 3]
in [Integer => a, Integer => b, *resto]
  puts "a=#{a}, b=#{b}, resto=#{resto}"
end

# Find pattern
case [1, 2, "erro", 4, 5]
in [*, String => s, *]
  puts "String encontrada: #{s}"
end

# Usado muito em parsers e processadores de eventos
def processar_evento(evento)
  case evento
  in { type: "user.created", payload: { id: Integer => id } }
    UserSetupJob.perform_later(id)
  in { type: "payment.failed", payload: { order_id: Integer => oid } }
    PaymentRetryJob.perform_later(oid)
  in { type: String => tipo }
    Rails.logger.warn "Evento desconhecido: #{tipo}"
  end
end
```

## 12. Functional Programming em Ruby

```ruby
# Method objects – transformar métodos em objetos/procs
def dobro(n) = n * 2

[1, 2, 3].map(&method(:dobro))   # [2, 4, 6]

# Composição de funções (Ruby 2.6+)
dobrar  = ->(n) { n * 2 }
somar1  = ->(n) { n + 1 }

# >> compõe da esquerda para direita
dobrar_depois_somar = dobrar >> somar1
dobrar_depois_somar.call(5)   # (5*2)+1 = 11

# << compõe da direita para esquerda
somar_depois_dobrar = dobrar << somar1
somar_depois_dobrar.call(5)   # (5+1)*2 = 12

# Curry – aplicação parcial de funções
multiplicar = ->(a, b) { a * b }
triplicar   = multiplicar.curry.(3)   # fixa a=3
triplicar.(10)   # 30
triplicar.(7)    # 21

[1, 2, 3, 4, 5].map(&multiplicar.curry.(10))
# [10, 20, 30, 40, 50]

# Pipeline funcional
resultado = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  .select(&:even?)
  .map { _1 ** 2 }     # _1 = primeiro argumento (Ruby 2.7+)
  .reject { _1 > 50 }
  .sum
# => 4 + 16 + 36 = 56
```

## 13. Struct e Data (Ruby 3.2+)

```ruby
# Struct – value object simples
Point = Struct.new(:x, :y) do
  def distancia_da_origem
    Math.sqrt(x**2 + y**2)
  end

  def to_s = "(#{x}, #{y})"
end

p = Point.new(3, 4)
p.x                      # 3
p.distancia_da_origem    # 5.0
p == Point.new(3, 4)     # true (compara valores!)

# Data (Ruby 3.2) – como Struct mas IMUTÁVEL
Coordenada = Data.define(:lat, :lon)

coord = Coordenada.new(lat: -23.5, lon: -46.6)
coord.lat          # -23.5
coord.frozen?      # true – sempre frozen!
coord.with(lat: 0) # retorna novo objeto
```

## 14. Refinements – Monkey Patch Seguro

```ruby
# Monkey patch global (evite!)
class String
  def palindromo?
    self == self.reverse
  end
end

# Refinement – scoped, não polui o namespace global
module PalindromeExtension
  refine String do
    def palindromo?
      self == reverse
    end
  end
end

class MeuParser
  using PalindromeExtension   # ativo APENAS aqui

  def verificar(str)
    str.palindromo?
  end
end

"arara".palindromo?    # NoMethodError! (fora do escopo)
MeuParser.new.verificar("arara")   # true
```

---

## 📝 Exercícios Rápidos

1. Implemente `flatten` sem usar o método nativo (use recursão).
2. Escreva um método que agrupe palavras pelo comprimento usando `group_by`.
3. Crie um módulo `Comparavel` com `maior_que?` e `menor_que?`.
4. Use `reduce` para implementar `map` e `select` do zero.
5. Implemente um Fibonacci lazy com `Enumerator`.
6. Use Pattern Matching para parsear eventos de webhook `{ type:, payload: }`.
7. Escreva uma pipeline funcional que: filtre strings com mais de 5 chars, capitalize, e remova duplicatas.

```ruby
# Gabarito exercício 7
palavras = ["ruby", "rails", "go", "python", "rust", "java", "elixir", "ruby"]
palavras
  .select { _1.length > 4 }
  .map(&:capitalize)
  .uniq
# => ["Rails", "Python", "Elixir"]

# Gabarito exercício 5 – Fibonacci lazy
fib = Enumerator.new do |y|
  a, b = 0, 1
  loop { y << a; a, b = b, a + b }
end
fib.lazy.first(10)  # [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
```
