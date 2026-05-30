# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { Faker::Name.name }
    password { "password123" }
    role { :member }
    active { true }

    trait :admin do
      role { :admin }
    end

    trait :moderator do
      role { :moderator }
    end

    trait :inactive do
      active { false }
    end
  end

  factory :profile do
    association :user
    bio { Faker::Lorem.paragraph }
    avatar_url { Faker::Avatar.image }
  end

  factory :permission do
    role { "moderator" }
    resource { "post" }
    action { "update" }
  end

  factory :comment do
    association :post
    association :user
    body { Faker::Lorem.paragraph }
  end

  factory :account do
    association :user
    balance { 100.0 }
  end

  factory :post do
    association :user
    sequence(:title) { |n| "Post Title #{n} about Rails" }
    body { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    status { :draft }
    slug { nil }

    trait :published do
      status { :published }
      published_at { Time.current }
    end

    trait :draft do
      status { :draft }
    end

    trait :archived do
      status { :archived }
    end
  end
end
