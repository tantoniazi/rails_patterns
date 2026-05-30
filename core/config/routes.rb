# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      resource :sessions, only: %i[create destroy] do
        post :refresh, on: :collection
      end

      resources :posts do
        resources :comments, only: %i[create index]
      end

      post "transfers", to: "transfers#create"

      namespace :reports do
        get "posts_summary", to: "posts#summary"
      end
      resources :users, only: %i[show update] do
        get :me, on: :collection
      end
    end
  end
end
