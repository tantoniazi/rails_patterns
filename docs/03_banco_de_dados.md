# 🗄️ Módulo 3 – Banco de Dados

## 1. SQL Básico e Avançado

```sql
-- SELECT básico
SELECT * FROM users WHERE active = true ORDER BY name LIMIT 10;

-- Filtros
SELECT * FROM posts
WHERE status = 'published'
  AND created_at >= '2024-01-01'
  AND title ILIKE '%rails%';

-- Funções de agregação
SELECT
  status,
  COUNT(*) AS total,
  AVG(views_count) AS media_views,
  MAX(created_at) AS mais_recente
FROM posts
GROUP BY status
HAVING COUNT(*) > 5
ORDER BY total DESC;
```

## 2. JOINs

```sql
-- INNER JOIN: só registros que têm correspondência nos dois lados
SELECT posts.title, users.name AS autor
FROM posts
INNER JOIN users ON users.id = posts.user_id;

-- LEFT OUTER JOIN: todos os posts, mesmo sem autor
SELECT posts.title, users.name
FROM posts
LEFT JOIN users ON users.id = posts.user_id;

-- Multi-join: posts com autor e quantidade de comentários
SELECT
  posts.id,
  posts.title,
  users.name AS autor,
  COUNT(comments.id) AS total_comentarios
FROM posts
INNER JOIN users    ON users.id    = posts.user_id
LEFT  JOIN comments ON comments.post_id = posts.id
GROUP BY posts.id, posts.title, users.name
ORDER BY total_comentarios DESC;

-- Subquery
SELECT * FROM users
WHERE id IN (
  SELECT DISTINCT user_id FROM posts WHERE status = 'published'
);

-- CTE (Common Table Expression)
WITH post_stats AS (
  SELECT user_id, COUNT(*) AS total_posts
  FROM posts
  GROUP BY user_id
)
SELECT users.name, post_stats.total_posts
FROM users
JOIN post_stats ON post_stats.user_id = users.id
WHERE post_stats.total_posts > 10;
```

## 3. Índices e Performance

```ruby
# Por que índices importam?
# Sem índice: full table scan = O(n)
# Com índice B-Tree: busca = O(log n)

# Criar índice simples
add_index :posts, :user_id
add_index :posts, :status
add_index :users, :email, unique: true

# Índice composto (ordem importa!)
# Útil para: WHERE status = 'published' ORDER BY created_at DESC
add_index :posts, [:status, :created_at]

# Índice parcial (só parte dos dados)
add_index :posts, :user_id, where: "status = 'published'"

# No PostgreSQL: índice para buscas LIKE
add_index :users, :name, using: :gin,
          opclass: { name: :gin_trgm_ops }  # requer pg_trgm

# Ver se o índice está sendo usado (EXPLAIN)
Post.where(status: :published).explain
# Procure por: Index Scan vs Seq Scan
```

```sql
-- EXPLAIN ANALYZE direto no Postgres
EXPLAIN ANALYZE
SELECT * FROM posts WHERE user_id = 1 AND status = 'published';

-- Resultado desejado: Index Scan
-- Resultado ruim:     Seq Scan (lê a tabela inteira)
```

## 4. N+1 Query – O Vilão das Entrevistas

```ruby
# ❌ PROBLEMA: N+1 Query
# 1 query para buscar posts + N queries (uma por post) para o autor
posts = Post.all
posts.each do |post|
  puts post.user.name   # SELECT * FROM users WHERE id = ?  (repete N vezes!)
end

# ✅ SOLUÇÃO 1: includes (preload separado ou JOIN automático)
posts = Post.includes(:user)
posts.each do |post|
  puts post.user.name   # sem query extra!
end

# ✅ SOLUÇÃO 2: eager_load (força LEFT JOIN em uma query)
posts = Post.eager_load(:user).where(users: { active: true })

# ✅ SOLUÇÃO 3: preload (sempre 2 queries separadas)
posts = Post.preload(:user, :comments, :tags)

# Detectar N+1 com Bullet gem (development)
# gem 'bullet', group: :development
# config/environments/development.rb
#   config.after_initialize do
#     Bullet.enable = true
#     Bullet.alert = true
#   end

# Exemplo avançado de N+1 aninhado
# ❌ Ruim
users = User.all
users.each do |user|
  user.posts.each do |post|
    post.comments.each { |c| puts c.body }
  end
end

# ✅ Bom
users = User.includes(posts: :comments)
```

## 5. Query Optimization – Técnicas

```ruby
# 1. select() – buscar só colunas necessárias
User.select(:id, :name, :email)   # não carrega avatar, bio, etc.

# 2. pluck() – retorna array puro sem objetos AR (muito mais rápido)
User.pluck(:id)                   # [1, 2, 3, ...]
User.pluck(:id, :name)            # [[1,"Ana"], [2,"Bob"]]
Post.where(status: :published).pluck(:user_id).uniq

# 3. exists? vs count vs any?
# exists? é mais rápido para checar existência
User.exists?(email: "a@b.com")    # SELECT 1 FROM users WHERE... LIMIT 1
User.where(active: true).exists?

# 4. find_in_batches para processar grandes volumes
Post.find_in_batches(batch_size: 1000) do |batch|
  batch.each { |post| process(post) }
end

# 5. Counter cache – evita COUNT em tempo real
# migration:
#   add_column :posts, :comments_count, :integer, default: 0
# model:
#   belongs_to :post, counter_cache: true
post.comments_count   # lê da coluna, não faz COUNT(*)

# 6. Raw SQL quando necessário
ActiveRecord::Base.connection.execute(<<~SQL)
  UPDATE posts SET views_count = views_count + 1
  WHERE id = #{id}
SQL

Post.where("created_at > ?", 30.days.ago)   # sempre use placeholders!
```

## 6. Transactions

```ruby
# Atomicidade: tudo ou nada
ActiveRecord::Base.transaction do
  conta_origem.update!(saldo: conta_origem.saldo - valor)
  conta_destino.update!(saldo: conta_destino.saldo + valor)
  Transferencia.create!(origem: conta_origem, destino: conta_destino, valor: valor)
  # Se qualquer update! falhar, TUDO é revertido (rollback)
end

# Salvar com lock para evitar race condition
# SELECT ... FOR UPDATE (bloqueia a linha)
Account.transaction do
  conta = Account.lock.find(id)
  raise "Saldo insuficiente" if conta.saldo < valor
  conta.update!(saldo: conta.saldo - valor)
end

# Optimistic locking (lock_version na tabela)
# migration: add_column :accounts, :lock_version, :integer, default: 0
conta1 = Account.find(1)
conta2 = Account.find(1)
conta1.update!(saldo: 100)   # OK, lock_version = 1
conta2.update!(saldo: 200)   # StaleObjectError! lock_version desatualizado

# Tratando a exceção
begin
  conta.update!(saldo: novo_saldo)
rescue ActiveRecord::StaleObjectError
  conta.reload
  retry  # ou trate o conflito
end
```

---

## 📝 Exercícios SQL

1. Encontre usuários que fizeram mais de 3 posts no último mês.
2. Liste os 5 posts com mais comentários, incluindo o nome do autor.
3. Calcule a receita total por categoria de produto.
4. Encontre usuários que nunca fizeram nenhum post (usando NOT EXISTS).

```sql
-- Exercício 1
SELECT users.id, users.name, COUNT(posts.id) AS total
FROM users
JOIN posts ON posts.user_id = users.id
WHERE posts.created_at >= NOW() - INTERVAL '1 month'
GROUP BY users.id, users.name
HAVING COUNT(posts.id) > 3;

-- Exercício 4
SELECT * FROM users
WHERE NOT EXISTS (
  SELECT 1 FROM posts WHERE posts.user_id = users.id
);
```
