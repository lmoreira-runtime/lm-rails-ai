require 'openai'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController
  
  @@request_system_message = "
  You are a highly skilled system designed to convert natural language user requests into Cypher (CQL) queries for a Neo4j database. The user may ask questions or request information about any information within the database.

  **DATABASE_SCHEMA**

  This is a JSON for describing the database nodes:
  ###NODES###
  
  This is a JSON for describing the database relationships between nodes:
  ###RELATIONSHIPS###

  Your task is to:
  1. Analyze the user request to understand the desired information.
  2. Translate the user's request into an optimized CQL query that accurately retrieves data from the Neo4j database.
  3. Generate only a valid Cypher query (CQL) based on the user's instructions. Do not include any comments, explanations, formatting, or additional text. Provide the query as plain text, with no leading or trailing characters.

  **EXAMPLE**

  ###EXAMPLE###
  "
  
  @@validation_system_message = "
  Your task is to prevent the CQL query of altering data in the database.
  If the query attempts to perform any delete or update actions (e.g., queries using DELETE, REMOVE, SET, MERGE, or CREATE for modifying data), respond with \"Error: Forbidden action\".
  Otherwise, simply respond \"OK\".
  "
  
  @@compliance_system_message = "
  You are a database expert specializing in Cypher Query Language (CQL) and schema design. Your task is to analyze the given CQL query and ensure it fully complies with the specified database schema.

  **Tasks**:
  
  - Schema Validation:

  Parse the provided DATABASE_SCHEMA JSON to extract node labels, relationship types, and property definitions.
  Verify that all nodes, relationships, and properties in the query match the schema.
  Ensure property data types are consistent with schema definitions.
  
  - Structural Consistency:

  Ensure the query uses correct labels, relationships, and property names.
  Verify the use of MATCH, WHERE, RETURN, and DISTINCT aligns with the schema structure and query intent.
  
  - Error Correction:

  If the query contains elements not defined in the schema or uses incorrect syntax, correct these issues.
  If any required elements are missing, add them.
  Ensure all changes comply with the schema and best practices for CQL.
  
  - Response Format:

  Output only the corrected Cypher query as plain text.
  No comments, explanations, or formatting.
  If the query is already valid and schema-compliant, return it unchanged.

  **DATABASE_SCHEMA**

  This is a JSON for describing the database nodes:
  ###NODES###
  
  This is a JSON for describing the database relationships between nodes:
  ###RELATIONSHIPS###

  **IMPORTANT NOTE**: The direction of the relationships has a direct impact on the query's correctness.
  "

  @@explanation_system_message = "
  You are an AI model that specializes in interpreting data results from a Neo4j database.
  Given the results in the format below, your task is to provide a clear and concise explanation for each entry, highlighting the key information such as the attributes n(area) and price.
  Your explanation must be written not with topics but as a continuous text.
  Please respond in the same language as the user request.

  # User request: ###USER_REQ###
  "

  def initialize()
    @@prompt_result_example ||= File.read(ENV['PROMPT_RESULT_EXAMPLE_PATH'])
  end

  def send_message
    user_message = params[:message]
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
    @db_nodes = Neo4jSchema.db_nodes
    @db_relationships = Neo4jSchema.db_relationships
    my_system_message = @@request_system_message
    my_system_message = my_system_message.sub("###NODES###", @db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @db_relationships)
    my_system_message = my_system_message.sub("###EXAMPLE###", @@prompt_result_example)
    cql = get_openai_response(user_input, my_system_message)
    puts ("# CQL: #{cql}\n")
    cql
  end

  def validate_cql(llm_response_cql)
    response = get_openai_response(llm_response_cql, @@validation_system_message)
    puts("# Validation: #{response}")
    response
  end

  def make_cql_comply(input_cql)
    @db_nodes = Neo4jSchema.db_nodes
    @db_relationships = Neo4jSchema.db_relationships
    my_system_message = @@compliance_system_message
    my_system_message = my_system_message.sub("###NODES###", @db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @db_relationships)
    cql = get_openai_response(input_cql, my_system_message)
    puts ("# COMPLYING CQL: #{cql}\n")
    cql
  end

  def query_neo4j(cql)
    session = ActiveGraph::Base.driver.session
    begin
      result = session.run(cql)
      nodes = result.to_a
      puts("# Nodes: #{nodes.length}")
      nodes
    ensure
      session.close
    end
  end

  def generate_explanation(user_input, nodes)
    nodes = nodes.map do |node|
      node.to_h
    end
    prompt = nodes.join('\n')
    my_system_message = @@explanation_system_message
    my_system_message = my_system_message.sub("###USER_REQ###", user_input)
    explanation = get_openai_response(prompt, my_system_message)
    explanation
  end

  def handle_user_query(user_input)
    generated_cql = translate_to_cql(user_input)
    response = validate_cql(generated_cql)

    if response.include?("Error:")
      return response
    end

    cql = make_cql_comply(generated_cql)
    
    results = query_neo4j(cql)
    explanation = generate_explanation(user_input, results)
  
    return explanation
  end

end
