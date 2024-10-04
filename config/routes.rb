Rails.application.routes.draw do
  root 'chatroom#index'
  post 'chatroom/send_message', to: 'chatroom#send_message'
end
