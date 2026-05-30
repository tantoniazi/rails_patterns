# frozen_string_literal: true

permissions = [
  { role: "moderator", resource: "post", action: "update" },
  { role: "moderator", resource: "post", action: "destroy" },
  { role: "member", resource: "post", action: "create" }
]

permissions.each do |attrs|
  Permission.find_or_create_by!(attrs)
end

admin = User.find_or_create_by!(email: "admin@example.com") do |user|
  user.name = "Admin User"
  user.password = "password123"
  user.role = :admin
end

member = User.find_or_create_by!(email: "member@example.com") do |user|
  user.name = "Member User"
  user.password = "password123"
  user.role = :member
end

[admin, member].each do |user|
  Account.find_or_create_by!(user: user) do |account|
    account.balance = user.admin? ? 1_000.0 : 500.0
  end
end

Post.find_or_create_by!(slug: "welcome-to-core") do |post|
  post.user = admin
  post.title = "Welcome to Core API"
  post.body = "This is a sample published post for development."
  post.status = :published
  post.published_at = Time.current
end

PostsSummary.refresh! if PostsSummary.table_exists?

puts "Seeded: admin=#{admin.email}, member=#{member.email}"
