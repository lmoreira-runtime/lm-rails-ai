require 'openai'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController
  def send_message
    user_message = params[:message]
    # response_message = get_openai_response(user_message)
    response_message = handle_user_query(user_message)
    render json: { user_message: user_message, response_message: response_message }
  end

  private

  def get_openai_response(message)
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
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

  def translate_to_cql(user_input)
    "match(n) return n limit 2"
  end

  def query_neo4j(cql)
    session = ActiveGraph::Base.driver.session
    begin
      result = session.run(cql)
      nodes = result.to_a
      nodes
    ensure
      session.close
    end
  end

  def generate_explanation(results)
    results = results.map do |result|
      #puts result.to_h
      result.to_h
    end
    results.join('\n')
  end

  def handle_user_query(user_input)
    cql = translate_to_cql(user_input)
    results = query_neo4j(cql)
    explanation = generate_explanation(results)
  
    explanation
  end

end
