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

  You MUST NOT generate a query for deleting or altering any data or relationships. 
  If the user asks you to delete or alter any data or relationship, you must respond \"Error: Forbidden action\".
  
  You MUST NOT add any text to the response other than the query itself.

  **EXAMPLE**

  ###EXAMPLE###
  "

  @@validation_system_message = "
  Your task is to process the input text according to the following rules:

  1. CQL Query Detection:
  Check if the input text is a valid CQL query. If it is not, return the response: \"Error: \" + input_text.
  
  2. Extra Text Removal:
  If the input text contains any extra or irrelevant text that does not belong to the CQL query, remove that extra text and return only the cleaned query.
  
  3. Forbidden Actions Check:
  If the query attempts to perform any delete or update actions (e.g., queries using DELETE, REMOVE, SET, MERGE, or CREATE for modifying data), respond with \"Error: Forbidden action\".
  
  4. Valid Query:
  If the input text is a valid, clean CQL query that does not attempt forbidden actions, return the query as it is.
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
    #puts my_system_message
    cql = get_openai_response(user_input, my_system_message)
    cql
  end

  def validate_cql(llm_response_cql)
    response = get_openai_response(llm_response_cql, @@validation_system_message)
    response
  end

  def query_neo4j(cql)
    puts cql
    session = ActiveGraph::Base.driver.session
    begin
      result = session.run(cql)
      nodes = result.to_a
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
    cql = translate_to_cql(user_input)
    response = validate_cql(cql)

    if response.include?("Error:")
      return response
    end
    
    results = query_neo4j(response)
    explanation = generate_explanation(user_input, results)
  
    return explanation
  end

end
