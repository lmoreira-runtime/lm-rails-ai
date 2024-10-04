require 'openai'

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY")
end

class ChatroomController < ApplicationController
  def send_message
    user_message = params[:message]
    response_message = get_openai_response(user_message)
    
    render json: { user_message: user_message, response_message: response_message }
  end

  private

  def get_openai_response(message)
    #my_api_key = ENV['OPENAI_API_KEY']
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          { role: "system", content: "You are a helpful assistant." },
          { role: "user", content: message }
        ]
      }
    )
    
    response['choices'][0]['message']['content'].strip
  rescue => e
    "Error: #{e.message}"
  end
end
