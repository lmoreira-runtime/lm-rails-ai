require './app/controllers/src/llms'
require './app/controllers/src/cql'
require './app/controllers/src/db'
require './app/controllers/src/json'
require './app/controllers/src/lvl1'
require './app/controllers/src/lvl2'
require './app/controllers/src/lvl3'
require './app/controllers/src/lvl4'
require './app/controllers/src/lvl5'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'

class ChatroomController < ApplicationController
  
  @@user_request_analysis_system_message = "
  You are an expert at analyzing natural language requests and extracting their essential components to facilitate the generation of Cypher (CQL) queries for a Neo4j database.
  Your task is to analyze the user's request and identify its key components, which will then be used to construct an accurate and optimized CQL query.

  **Key Components to Identify**
    1. Action: What the user intends to perform (e.g., list, count, find).
    2. Entities: The main objects or concepts mentioned in the request.
    3. Relationships: Any relationships between entities that need to be considered based on the user's request.
    4. Conditions/Filters: Any specific constraints, attributes, or requirements mentioned in the user's request (e.g., location, price range).
    5. Output Requirements: What the user wants in the result (e.g., specific attributes, aggregates).
    6. Sorting Preferences (if applicable): Instructions on ordering the results (e.g., ascending, descending).

  **Instructions**
  Use the provided schema to ensure that entities and relationships are aligned with the database structure.
  Do not include Cypher syntax in this step. Focus solely on extracting and organizing the key components.
  Provide the output as plain text with no leading or trailing characters, and no code block delimiters.

  **Database Schema**

  This is a JSON describing the database nodes: ###NODES###

  This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###

  
  **Output Format**
  Return the extracted information as structured JSON:

  {
    \"action\": \"list/count/find\",
    \"entities\": [\"entity1\", \"entity2\"],
    \"relationships\": [\"relationship1\", \"relationship2\"],
    \"conditions\": {
      \"attribute1\": \"value1\",
      \"attribute2\": \"value2\"
    },
    \"sorting\": {
      \"attribute\": \"asc/desc\"
    },
    \"output\": [\"attribute1\", \"attribute2\"]
  }
  "

  @@map_data_model_system_message = "
  You are an expert in Cypher (CQL) and skilled at translating extracted user intents into the structural components of a Neo4j database.
  Your task is to map high-level concepts (entities, relationships, attributes, and conditions) from the user's request to the database schema, ensuring that all mappings strictly adhere to the schema.

  **Input**  
  You will receive:  
  1. The user's request.
  2. Extracted Components: A structure containing the key elements from the user's request (e.g., action, entities, relationships, conditions, sorting, and output).  

  **Your Task**  
  1. Map Entities: Match each entity in the request to its corresponding node(s) in the schema.  
  2. Map Relationships: Identify and validate the relationships connecting the nodes, ensuring adherence to the directionality specified in the schema.  
  3. Map Conditions and Attributes: Verify that the conditions or filters correspond to valid attributes in the nodes or relationships.  
  4. Map Sorting and Output: Confirm that sorting preferences and requested outputs align with the attributes defined in the schema.  
  5. Return a Valid Mapped Structure: Provide a complete mapping of the request elements to the database structure.

  **Output Format**  
  Return the mapping in the following JSON structure:  

  {
    \"action\": \"list/count/find\",
    \"nodes\": {
      \"entity1\": \"MappedNode1\",
      \"entity2\": \"MappedNode2\"
    },
    \"relationships\": [
      {
        \"source\": \"MappedNode1\",
        \"relationship\": \"RelationshipType\",
        \"target\": \"MappedNode2\"
      }
    ],
    \"conditions\": {
      \"MappedNode1.attribute\": \"value1\",
      \"MappedNode2.attribute\": \"value2\"
    },
    \"sorting\": {
      \"node\": \"MappedNode\",
      \"attribute\": \"attributeName\",
      \"order\": \"asc/desc\"
    },
    \"output\": [\"MappedNode1.attribute\", \"MappedNode2.attribute\"]
  }

  Provide the output as plain text with no leading or trailing characters, and no code block delimiters.

  **Database Schema**

  This is a JSON describing the database nodes: ###NODES###

  This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###
  "

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

  @@analyze_system_message = "
  You are an expert in the Cypher Query Language (CQL) and adept at understanding user intent.
  Your primary task is to evaluate Cypher queries (CQL) generated by another LLM based on a user's natural language request. 
  You will receive two inputs:  

  1. **User Message**: The natural language request from the user.
  2. **Generated Query**: A Cypher query designed to fulfill the user request.

  Your responsibilities are:  
  - **Interpret the User Request**: Determine the intended database information retrieval.
  - **Analyze the Cypher Query**: Check whether the provided query fulfills the user request logically and correctly.
  - **Validate the Query**:  
    - If the query accurately reflects the user's request, return positive feedback.  
    - If the query is incorrect, incomplete, or illogical in the context of the user request, return negative feedback and explain how can the query be corrected.

  ### Response Format  

  You must always respond in the following JSON structure:

  **For a logically sound query:**  
  {
    \"valid\": true,
    \"comment\": \"Accurate query\"
  }

  **For a logically incorrect query:**  
  {
    \"valid\": false,
    \"comment\": [explanation of the query's error and how it should be corrected],
  }
  "

  @@meet_expectation_system_message = "
  You are an expert in Cypher Query Language (CQL), specialized in analyzing and correcting queries.
  Your task is to evaluate Cypher queries based on a user’s request and specific guidance provided.
  You must correct the query to ensure it accurately retrieves the intended information.

  **Instructions:**

  1. **Input Structure:**
    - **User Request**: A natural language description of the user's original intent.
    - **Unreliable Query**: The unreliable or incorrect Cypher query generated previously.
    - **Guidance**: Specific instructions on how to adjust the query to meet the user’s expectations.

  2. **Key Considerations:**
    - **Apply the Guidance provided to correct the query.** Ensure it meets the user's expectations as described in User Request.
    - **Maintain simplicity and accuracy.** Only make changes necessary to align the query with the intended purpose.
    
  3. **Output Format:**
    - Return the corrected Cypher query in **plain text** format.
    - DO NOT INCLUDE any leading or trailing characters, and no code block delimiters.
  "
  
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
    my_system_message = @@user_request_analysis_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
    result = get_openai_response(user_input, my_system_message, "gpt-4o")
    # result = get_ollama_response(user_input, my_system_message, "llama3.1")
    puts ("# JSON: #{result}\n")
    result
  end

  def map_data_model(user_input, extracted_components)
    my_system_message = @@map_data_model_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
    my_user_message = "**User Request**: #{user_input}\n\n**Extracted Components**: #{extracted_components}"
    result = get_openai_response(user_input, my_system_message, "gpt-4o-mini")
    # result = get_ollama_response(my_user_message, my_system_message, "llama3.1")
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

  def analyze_cql_query(user_message, generated_query)
    my_system_message = @@analyze_system_message
    my_user_message = "**User Message**: #{user_message}\n\n**Generated Query**: #{generated_query}"
    result = get_openai_response(my_user_message, my_system_message, "gpt-4o-mini")
    puts "# QUERY ANALYSIS: #{result}\n"
    result
  end

  def fix_cql_to_meet_expectation(user_message, unreliable_query, guidance)
    my_system_message = @@meet_expectation_system_message
    my_user_message = "**User Request**: #{user_message}\n\n**Unreliable Query**: #{unreliable_query}\n\n**Guidance**: #{guidance}"
    result_query = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    puts "# (UN)RELIABLE QUERY: #{result_query}\n"
    result_query
  end

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
      generated_query = generate_query_lvl1(user_input, extracted_components_hash)
    when 2
      generated_query = generate_query_lvl2(user_input, extracted_components_hash)
    when 3
      generated_query = generate_query_lvl3(user_input, extracted_components_hash)
    when 4
      generated_query = generate_query_lvl4(user_input, extracted_components_hash)
    when 5
      generated_query = generate_query_lvl5(user_input, extracted_components_hash)
    else
      generated_query = ""
    end

    reliable_query = clean_cql_query(generated_query)
    num_tries = 4
    analysis = analyze_cql_query(user_input, reliable_query)
    analysis_hash = parse_json_with_bom_removal(analysis)
    while analysis_hash["valid"] == false && num_tries > 0
      num_tries -= 1
      reliable_query = fix_cql_to_meet_expectation(user_input, reliable_query, analysis_hash["comment"])
      reliable_query = clean_cql_query(reliable_query)
      analysis = analyze_cql_query(user_input, reliable_query)
      analysis_hash = parse_json_with_bom_removal(analysis)
    end
    return reliable_query + "</br></br>" + analysis

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
