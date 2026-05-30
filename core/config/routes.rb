# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      resource :sessions, only: %i[create destroy] do
        post :refresh, on: :collection
      end

      resources :posts
      resources :users, only: %i[show update] do
        get :me, on: :collection
      end
    end
  end
end
