require 'openai'
require 'neo4j_ruby_driver'
require './config/initializers/neo4j'
require 'json'

class ChatroomController < ApplicationController
  
  @@request_system_message = "
  You are a highly skilled system designed to convert natural language user requests into Cypher (CQL) queries for a Neo4j database.

  **DATABASE_SCHEMA**

  This is a JSON describing the database nodes: ###NODES###

  This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###

  Your task is to:

  1. Analyze the user request to understand the desired information.
  2. Ensure strict adherence to relationship direction as specified in the database schema.
  3. Translate the user's request into a valid and optimized CQL query. The query must accurately reflect the direction of relationships.
  3. Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters.
  
  **EXAMPLE**

  ###EXAMPLE###
  "
  
  @@validation_system_message = "
  Your task is to prevent the CQL query of altering data in the database.
  If the query attempts to perform any delete or update actions (e.g., queries using DELETE, REMOVE, SET, MERGE, or CREATE for modifying data), respond with \"Error: Forbidden action\".
  Otherwise, simply respond \"OK\".
  "
  
  @@compliance_system_message = "
  You are an LLM specialized in generating Cypher (CQL) queries for a Neo4j database.
  Your task is to:

  1. Analyze the provided CQL query and error message.
  2. Correct the CQL query to match the expected relationship direction and structure, as indicated in the error message.
  3. Return only the corrected CQL query in plain text. Do not include any additional text, comments, explanations or code block delimiters.
  "

  @@explanation_system_message = "
  You are an AI model that specializes in interpreting data results from a Neo4j database.
  Given the results in the format below, your task is to provide a clear and concise explanation for each entry, highlighting the key information such as the attributes n(area) and price.
  Your explanation must be written not with topics but as a continuous text.
  Please respond in the same language as the user request.

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
    my_system_message = @@request_system_message
    my_system_message = my_system_message.sub("###NODES###", @@db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", @@db_relationships)
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

  def extract_patterns(cql_query)
    result = []

    forward_pattern = /\((\w+)(?::(\w+))?\)-\[:(\w+)\]->\((\w+)(?::(\w+))?\)/
    result += cql_query.scan(forward_pattern).map { |match| match + ['->'] }

    reverse_pattern = /\((\w+)(?::(\w+))?\)<-\[:(\w+)\]-\((\w+)(?::(\w+))?\)/
    result += cql_query.scan(reverse_pattern).map { |match| match + ['<-'] }

    result
  end

  def parse_json_with_bom_removal(json_string)
    # Remove BOM if it exists
    json_string = json_string.sub("\uFEFF", '')
    JSON.parse(json_string)
  end

  def validate_relationships(cql_query)
    result = { "valid": nil, "errors": [], "corrections": [] }
    nodes_n_labels = {}
    patterns = extract_patterns(cql_query)
    relationships = parse_json_with_bom_removal(@@db_relationships)

    patterns.each do |node1, label1, rel_type, node2, label2, direction|
      relationship = relationships.find { |rel| rel["RelationshipType"] == rel_type }
      if label1 != nil
        nodes_n_labels[node1] = label1
      else
        if nodes_n_labels.key?(node1)
          label1 = nodes_n_labels[node1]
        end
      end
      if label2 != nil
        nodes_n_labels[node2] = label2
      else
        if nodes_n_labels.key?(node2)
          label2 = nodes_n_labels[node2]
        end
      end

      # if direction == '->'
      #   puts "#### (#{node1}:#{label1})-[:#{rel_type}]->(#{node2}:#{label2})"
      # else
      #   puts "#### (#{node1}:#{label1})<-[:#{rel_type}]-(#{node2}:#{label2})"
      # end

      # puts "# nodes_n_labels: #{nodes_n_labels.inspect}"
  
      unless relationship
        return "Invalid relationship type: #{rel_type}"
      end

      expected_labels = if direction == '->'
        [label1, label2]
      else
        [label2, label1]
      end

      unless relationship["StartNodeLabels"].include?(expected_labels[0]) && relationship["EndNodeLabels"].include?(expected_labels[1])
        result[:valid] = false
        result[:errors] << "Incorrect nodes for relationship #{rel_type}: expected #{relationship['StartNodeLabels']} -> #{relationship['EndNodeLabels']}, got #{expected_labels[0]} -> #{expected_labels[1]}"
        correction = {
          "before": [expected_labels[0], rel_type, expected_labels[1]],
          "after": [relationship["StartNodeLabels"][0], rel_type, relationship["EndNodeLabels"][0]]
        }
        result[:corrections] << correction
      end

    end
  
    if result[:valid].nil?
      result[:valid] = true
    end
    result
  end

  def fix_relationships(query, corrections)
    corrections.each do |correction|
      before = correction[:before]
      after = correction[:after]
  
      before_start, before_rel, before_end = before
      after_start, after_rel, after_end = after
  
      if query.include?("<-[:#{before_rel}]-")
        before_pattern = /
          \(\s*(\w*)\s*(?::#{before_end})?\s*\)\s*
          <-\[:#{before_rel}\]-\s*
          \(\s*(\w*)\s*(?::#{before_start})?\s*\)
        /x
      else
        before_pattern = /
          \(\s*(\w*)\s*(?::#{before_start})?\s*\)\s*
          -\[:#{before_rel}\]->\s*
          \(\s*(\w*)\s*(?::#{before_end})?\s*\)
        /x
      end

      after_pattern = if query.include?("<-[:#{after_rel}]-")
                      "(\\1:#{after_start})-[:#{after_rel}]->(\\2:#{after_end})"
                    else
                      "(\\1:#{after_end})<-[:#{after_rel}]-(\\2:#{after_start})"
                    end

      query.gsub!(before_pattern, after_pattern)
    end
  
    query
  end
  
  

  def make_cql_comply(query, errors)
    my_system_message = @@compliance_system_message
    my_user_message = "**QUERY**\n\n#{query}\n\n**ERRORS**\n\n#{errors.join("\n")}"
    puts "# ERRORS: #{errors.join("\n")}"
    cql = get_openai_response(my_user_message, my_system_message)
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

    validation = validate_relationships(generated_cql)
    if validation[:valid] == false
      puts ("# validation: #{validation.inspect}")
      generated_cql = fix_relationships(generated_cql, validation[:corrections])
      puts ("# corrected cql: #{generated_cql}")
    end

    cql = generated_cql
    
    results = query_neo4j(cql)
    explanation = generate_explanation(user_input, results)
  
    return explanation
  end

end
