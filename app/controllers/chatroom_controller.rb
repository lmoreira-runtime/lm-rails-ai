require './app/controllers/src/llms'
require './app/controllers/src/db'
require './app/controllers/src/json'
require './app/controllers/src/query_generation'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController
  @@db_nodes = Neo4jSchema.db_nodes
  @@db_relationships = Neo4jSchema.db_relationships

  def initialize()
    @@prompt_result_example ||= File.read(ENV['PROMPT_RESULT_EXAMPLE_PATH'])
  end

  def send_message
    user_message = params[:message]
    response_message = handle_user_query(user_message)
    render json: { user_message: user_message, response_message: response_message }
  end

  private

  def generate_explanation(user_input, nodes)
    nodes = nodes.map do |node|
      node.to_h
    end
    prompt = nodes.join('\n')
    my_system_message = $explanation_system_message
    my_system_message = my_system_message.sub("###USER_REQ###", user_input)
    explanation = get_openai_response(prompt, my_system_message, "gpt-4o-mini")
    explanation
  end

  def handle_user_query(user_input)
    generated_query = query_generation(user_input)

    error_free_cql = generated_query

    num_tries = 3
    results = query_neo4j(error_free_cql)
    while results[:result] == nil and num_tries > 0
      num_tries -= 1
      error_free_cql = fix_cql(error_free_cql, results[:error])
      error_free_cql = clean_cql_query(error_free_cql)
      results = query_neo4j(error_free_cql)
    end

    if results[:result] == nil
      explanation = "An error has occurred. Please try again."
    else
      explanation = generate_explanation(user_input, results[:result])
    end
    explanation.gsub! "\n", "</br>"
    return explanation
  end

end
