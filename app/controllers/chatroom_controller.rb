require './app/controllers/src/llms'
require './app/controllers/src/cql'
require './app/controllers/src/db'
require './app/controllers/src/json'
require './app/controllers/src/lvl1'
require './app/controllers/src/lvl2'
require './app/controllers/src/lvl3'
require './app/controllers/src/lvl4'
require './app/controllers/src/lvl5'
require './app/controllers/src/prompts'
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

  def analyze_user_request(user_input)
    my_system_message = $user_request_analysis_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
    result = get_openai_response(user_input, my_system_message, "gpt-4o")
    # result = get_ollama_response(user_input, my_system_message, "llama3.1")
    puts ("# JSON: #{result}\n")
    result
  end

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
    extracted_components = analyze_user_request(user_input)
    extracted_components_hash = parse_json_with_bom_removal(extracted_components)
    complexity = determine_query_complexity(extracted_components_hash)

    case complexity
    when 1
      puts "** LEVEL 1 **"
      generated_query = generate_query_lvl1(user_input, extracted_components_hash)
    when 2
      puts "** LEVEL 2 **"
      generated_query = generate_query_lvl2(user_input, extracted_components_hash)
    when 3
      puts "** LEVEL 3 **"
      generated_query = generate_query_lvl3(user_input, extracted_components_hash)
    when 4
      puts "** LEVEL 4 **"
      generated_query = generate_query_lvl4(user_input, extracted_components_hash)
    when 5
      puts "** LEVEL 5 **"
      generated_query = generate_query_lvl5(user_input, extracted_components_hash)
    else
      generated_query = "ERROR: operation not permitted"
    end

    return generated_query

    # fixed_relationships_query = reliable_query
    # num_tries = 2
    # validation = validate_relationships(fixed_relationships_query, @@db_relationships)
    # while validation[:valid] == false and num_tries > 0
    #   num_tries -= 1
    #   # puts ("# Relationships validation: #{validation.inspect}")
    #   fixed_relationships_query = fix_relationships(fixed_relationships_query, validation[:corrections])
    #   validation = validate_relationships(fixed_relationships_query, @@db_relationships)
    # end

    # if num_tries < 2
    #   puts ("# FIXED RELATIONSHIPS CQL: #{fixed_relationships_query}")
    # end

    error_free_cql = generated_query

    num_tries = 3
    results = query_neo4j(error_free_cql)
    while results[:result] == nil and num_tries > 0
      num_tries -= 1
      error_free_cql = fix_cql(error_free_cql, results[:error])
      error_free_cql = clean_cql_query(error_free_cql)
      results = query_neo4j(error_free_cql)
    end

    #puts "# results: #{results}"
    if results[:result] == nil
      explanation = "An error has occurred. Please try again."
    else
      explanation = generate_explanation(user_input, results[:result])
      #puts "# explanation: #{explanation}"
      # if reliable == false
      #   explanation = "WARNING: Potentially unreliable information.\n\n" + explanation
      # end
    end
    explanation.gsub! "\n", "</br>"
    return explanation
  end

end
