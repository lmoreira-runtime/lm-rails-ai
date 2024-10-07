require 'openai'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController

  @@explanation_system_message = "
  You are an AI model that specializes in interpreting data results from a Neo4j database.
  Given the results in the format below, your task is to provide a clear and concise explanation for each entry, highlighting the key information such as the attributes n(area) and price.
  Your explanation must be written not with topics but as a continuous text in an informal speech.

  Data Format:

  Each entry represents an apartment with the following attributes:
  n: A numerical value representing the area
  price: The market price of the apartment
  index: The position of the entry in the result set
  @labels: The category of the entry (e.g., :Apartamento)
  "

  def send_message
    user_message = params[:message]
    # response_message = get_openai_response(user_message)
    response_message = handle_user_query(user_message)
    render json: { user_message: user_message, response_message: response_message }
  end

  private

  def get_openai_response(prompt, system_message)
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: system_message},
          { role: "user", content: prompt }
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

  def generate_explanation(nodes)
    nodes = nodes.map do |node|
      node.to_h
    end
    prompt = nodes.join('\n')
    explanation = get_openai_response(prompt, @@explanation_system_message)
    explanation
  end

  def handle_user_query(user_input)
    cql = translate_to_cql(user_input)
    results = query_neo4j(cql)
    explanation = generate_explanation(results)
  
    explanation
  end

end
