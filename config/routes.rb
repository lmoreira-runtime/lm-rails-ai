Rails.application.routes.draw do
  root 'chatroom#index'
  post 'chatroom/send_message', to: 'chatroom#send_message'
  resources :questions, only: [:index, :new, :create]
  post 'questions/new', to: 'questions#create'
  get 'questions/preprocess', to: 'questions#preprocess'
  get 'questions/processing', to: 'questions#processing'
  get 'questions/start', to: 'questions#start'
  get 'questions/status', to: 'questions#status'

end
