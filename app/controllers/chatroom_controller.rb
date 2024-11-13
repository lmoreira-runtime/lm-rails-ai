require './app/controllers/src/llms'
require './app/controllers/src/cql'
require './app/controllers/src/db'
require './app/controllers/src/json'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController
  
  @@request_system_message = "
  You are an expert in Cypher (CQL) and highly efficient at transforming natural language requests into precise queries for a Neo4j database.

  **DATABASE_SCHEMA**

  This is a JSON describing the database nodes: ###NODES###

  This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###

  Your task is to:

  1. Analyze the user request to understand the desired information.
  2. Ensure strict adherence to relationship direction as specified in the database schema.
  3. Translate the user's request into a valid and optimized CQL query. The query must accurately reflect the direction of relationships.
  3. Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters, and no code block delimiters.
  
  **EXAMPLE**

  ###EXAMPLE###
  "
  
  @@validation_system_message = "
  Your task is to prevent the CQL query of altering data in the database.
  If the query attempts to perform any delete or update actions (e.g., queries using DELETE, REMOVE, SET, MERGE, or CREATE for modifying data), respond with \"Error: Forbidden action\".
  Otherwise, simply respond \"OK\".
  "

  @@fixing_query_system_message = "
  You are an expert in Cypher (CQL), used to query Neo4j graph databases.
  Your task is to assist the user in crafting valid, optimized, and efficient CQL queries.

  The user will provide you with:
  1. A flawed CQL query.
  2. An error message returned by the database.

  Your role is to:

  1. **Understand the intent** behind the user’s query.
  2. **Analyze the provided error message** to pinpoint specific issues.
  3. **Identify and correct errors** in syntax, structure, or logic based on the error message and query context.
  4. **Provide a valid, optimized CQL query** that fulfills the user’s intended request.

  When correcting the query, ensure:
  - Syntax is correct and compliant with CQL standards.
  - The query is optimized for performance where applicable.
  - Any missing elements (e.g., WHERE clauses, MATCH conditions) are logically completed based on the provided context.

  Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters, and no code block delimiters.
"

  @@explanation_system_message = "
  You are an AI model that specializes in interpreting data results from a Neo4j database.
  Given the results below, your task is to provide a clear and concise explanation for each entry, highlighting the key information.
  Your explanation by default should be written in a continuous text, unless otherwise specified by the user.
  You must respond in the same language as the user request.

  # User request: ###USER_REQ###
  "

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

  def translate_to_cql(user_input)
    my_system_message = @@request_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
    my_system_message = my_system_message.sub("###EXAMPLE###", @@prompt_result_example)
    cql = get_openai_response(user_input, my_system_message, "gpt-4o")
    puts ("# CQL: #{cql}\n")
    cql
  end

  def validate_cql(llm_response_cql)
    response = get_openai_response(llm_response_cql, @@validation_system_message, "gpt-4o-mini")
    puts("# Security validation: #{response}")
    response
  end

  def fix_cql(query, error)
    my_system_message = @@fixing_query_system_message
    my_user_message = "**QUERY**: #{query}\n\n**ERROR**: #{error}"
    cql = get_openai_response(my_user_message, my_system_message, "gpt-4o-mini")
    puts ("# FIXED CQL: #{cql}\n")
    cql
  end

  def generate_explanation(user_input, nodes)
    nodes = nodes.map do |node|
      node.to_h
    end
    prompt = nodes.join('\n')
    my_system_message = @@explanation_system_message
    my_system_message = my_system_message.sub("###USER_REQ###", user_input)
    explanation = get_openai_response(prompt, my_system_message, "gpt-4o")
    explanation
  end

  def handle_user_query(user_input)
    generated_cql = translate_to_cql(user_input)
    generated_cql = clean_cql_query(generated_cql)
    response = validate_cql(generated_cql)

    if response.include?("Error:")
      return response
    end

    validation = validate_relationships(generated_cql, @@db_relationships)
    if validation[:valid] == false
      puts ("# Relationships validation: #{validation.inspect}")
      generated_cql = fix_relationships(generated_cql, validation[:corrections])
      puts ("# FIXED RELATIONSHIPS CQL: #{generated_cql}")
    end

    cql = generated_cql

    num_tries = 3
    results = query_neo4j(cql)
    while results[:result] == nil and num_tries > 0
      num_tries -= 1
      cql = fix_cql(cql, results[:error])
      cql = clean_cql_query(cql)
      results = query_neo4j(cql)
    end

    #puts "# results: #{results}"
    if results[:result] == nil
      explanation = "An error has occurred. Please try again."
    else
      explanation = generate_explanation(user_input, results[:result])
    end
    return explanation
  end

end
