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

  @@generate_query_system_message = "
  You are an expert in Cypher (CQL) and skilled at creating database queries that satisfy user requests.
  Based on the user's intent and the mapped components, your task is to generate a Cypher query that fulfills the user’s request.
  The query should focus on including the key nodes, relationships, and basic structure necessary to answer the request.

  **Input**  
  You will receive:  
  1. User Request: The original natural language request from the user.  
  2. Mapped Components: A structured JSON detailing the mapped nodes, relationships, conditions, sorting, and output attributes.  

  **Your Task**  
  Generate a Cypher Query:
    - Construct a query that matches the nodes and relationships identified in the mapping.  
    - The query should fully satisfy the user’s request based on the mapped components.
    - Ensure the query adheres to Cypher syntax and relationship directionality as defined in the mapping.
    - Make the query as simple as possible.  

  **Output Format**  
  Provide the draft Cypher query as plain text with no extra characters or delimiters, and no code block delimiters..  

  **Database Schema**

  This is a JSON describing the database nodes: ###NODES###

  This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###
"

  # @@request_system_message = "
  # You are an expert in Cypher (CQL) and highly efficient at transforming natural language requests into precise queries for a Neo4j database.

  # **DATABASE_SCHEMA**

  # This is a JSON describing the database nodes: ###NODES###

  # This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###

  # Your task is to:

  # 1. Analyze the user request to understand the desired information.
  # 2. Ensure strict adherence to relationship direction as specified in the database schema.
  # 3. Translate the user's request into a valid and optimized CQL query. The query must accurately reflect the direction of relationships.
  # 3. Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters, and no code block delimiters.
  
  # **EXAMPLE**

  # ###EXAMPLE###
  # "

  # @@validation_system_message = "
  # Your task is to prevent the CQL query of altering data in the database.
  # If the query attempts to perform any delete or update actions (e.g., queries using DELETE, REMOVE, SET, MERGE, or CREATE for modifying data), respond with \"Error: Forbidden action\".
  # Otherwise, simply respond \"OK\".
  # "

  # @@fixing_query_system_message = "
  # You are an expert in Cypher (CQL), used to query Neo4j graph databases.
  # Your task is to assist the user in crafting valid, optimized, and efficient CQL queries.

  # The user will provide you with:
  # 1. A flawed CQL query.
  # 2. An error message returned by the database.

  # Your role is to:

  # 1. **Understand the intent** behind the user’s query.
  # 2. **Analyze the provided error message** to pinpoint specific issues.
  # 3. **Identify and correct errors** in syntax, structure, or logic based on the error message and query context.
  # 4. **Provide a valid, optimized CQL query** that fulfills the user’s intended request.

  # When correcting the query, ensure:
  # - Syntax is correct and compliant with CQL standards.
  # - The query is optimized for performance where applicable.
  # - Any missing elements (e.g., WHERE clauses, MATCH conditions) are logically completed based on the provided context.

  # Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters, and no code block delimiters.
  # "

  # @@explanation_system_message = "
  # You are an AI model that specializes in interpreting data results from a Neo4j database.
  # Given the results below, your task is to provide a clear and concise explanation for each entry, highlighting the key information.
  # Your explanation by default should be written in a continuous text, unless otherwise specified by the user.
  # You must respond in the same language as the user request.

  # # User request: ###USER_REQ###
  # "

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

  def generate_query(user_input, mapped_components)
    my_system_message = @@generate_query_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
    my_user_message = "**User Request**: #{user_input}\n\n**Mapped Components**: #{mapped_components}"
    result = get_openai_response(user_input, my_system_message, "gpt-4o-mini")
    # result = get_ollama_response(my_user_message, my_system_message, "llama3.1")
    puts ("# CQL: #{result}\n")
    result
  end

  # def translate_to_cql(user_input)
  #   my_system_message = @@request_system_message
  #   my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
  #   my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
  #   my_system_message = my_system_message.sub("###EXAMPLE###", @@prompt_result_example)
  #   cql = get_openai_response(user_input, my_system_message, "gpt-4o")
  #   puts ("# CQL: #{cql}\n")
  #   cql
  # end

  # def validate_cql_security(llm_response_cql)
  #   response = get_openai_response(llm_response_cql, @@validation_system_message, "gpt-4o-mini")
  #   puts("# Security validation: #{response}")
  #   response
  # end

  # def fix_cql(query, error)
  #   my_system_message = @@fixing_query_system_message
  #   my_user_message = "**QUERY**: #{query}\n\n**ERROR**: #{error}"
  #   cql = get_openai_response(my_user_message, my_system_message, "gpt-4o-mini")
  #   puts ("# FIXED CQL: #{cql}\n")
  #   cql
  # end

  # def generate_explanation(user_input, nodes)
  #   nodes = nodes.map do |node|
  #     node.to_h
  #   end
  #   prompt = nodes.join('\n')
  #   my_system_message = @@explanation_system_message
  #   my_system_message = my_system_message.sub("###USER_REQ###", user_input)
  #   explanation = get_openai_response(prompt, my_system_message, "gpt-4o-mini")
  #   explanation
  # end

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

    # reliable_query = clean_cql_query(generated_query)
    # num_tries = 4
    # analysis = analyze_cql_query(user_input, reliable_query)
    # analysis_hash = parse_json_with_bom_removal(analysis)
    # while analysis_hash["valid"] == false && num_tries > 0
    #   num_tries -= 1
    #   reliable_query = fix_cql_to_meet_expectation(user_input, reliable_query, analysis_hash["comment"])
    #   reliable_query = clean_cql_query(reliable_query)
    #   analysis = analyze_cql_query(user_input, reliable_query)
    #   analysis_hash = parse_json_with_bom_removal(analysis)
    # end

    # generated_cql = translate_to_cql(user_input)
    # generated_cql = clean_cql_query(generated_cql)
    
    
    # if analysis_hash["valid"] == true
    #   reliable = true
    # else
    #   reliable = false
    # end
      
    # response = validate_cql_security(reliable_query)
    # if response.include?("Error:")
    #   return response
    # end

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

    # error_free_cql = fixed_relationships_query

    # num_tries = 3
    # results = query_neo4j(error_free_cql)
    # while results[:result] == nil and num_tries > 0
    #   num_tries -= 1
    #   error_free_cql = fix_cql(error_free_cql, results[:error])
    #   error_free_cql = clean_cql_query(error_free_cql)
    #   results = query_neo4j(error_free_cql)
    # end

    # #puts "# results: #{results}"
    # if results[:result] == nil
    #   explanation = "An error has occurred. Please try again."
    # else
    #   explanation = generate_explanation(user_input, results[:result])
    #   #puts "# explanation: #{explanation}"
    #   if reliable == false
    #     explanation = "WARNING: Potentially unreliable information.\n\n" + explanation
    #   end
    # end
    # explanation.gsub! "\n", "</br>"
    # return explanation
  end

end
