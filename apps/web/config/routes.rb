Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "dashboard#index"

  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  resources :library_entries, only: %i[index show]

  namespace :admin do
    root "users#index"
    resources :users, only: %i[index]
    resources :documents, only: %i[index]
  end

  namespace :api do
    namespace :v1 do
      post "/session", to: "sessions#create"
      delete "/session", to: "sessions#destroy"

      resources :library_entries, only: %i[index] do
        collection do
          post :register
        end
      end

      resource :reader_session, only: %i[show] do
        post :upsert
      end

      resources :bookmarks, only: %i[index] do
        collection do
          post :upsert
        end
      end

      resources :highlights, only: %i[index] do
        collection do
          post :upsert
        end
      end

      resources :notes, only: %i[index] do
        collection do
          post :upsert
        end
      end
    end
  end
end
