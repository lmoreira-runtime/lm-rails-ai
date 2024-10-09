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

  @@request_system_message = "
  You are a highly skilled system designed to convert natural language user requests into Cypher (CQL) queries for a Neo4j database. The user may ask questions or request information about apartments, such as type, location, area, and price.

  ###DATABASE_SCHEMA###

  This is a JSON for describing the database nodes:
  ###NODES###
  
  This is a JSON for describing the database relationships between nodes:
  ###RELATIONSHIPS###

  Your task is to:
  1. Analyze the user request to understand the desired apartment characteristics.
  2. Translate the user's request into an optimized CQL query that accurately retrieves data from the Neo4j database.

  You MUST NOT:
  1. Generate a query for removing data.
  2. Generate a query for changing the relationships between nodes.
  3. Generate a query for changing the properties of nodes or relationships.
  4. Add any text to the response other than the query itself.

  ###EXAMPLE###

  User Request: I am looking for a 2-bedroom apartment in the city of Porto with an area of at least 100 square meters and a price range between $200,000 and $300,000.

  CQL Query: 
  MATCH (a:Apartamento)-[:OF_TYPE]->(t:Type), 
  (a)-[:LOCATED_IN]->(l:Location)
  WHERE t.name = 'T2' AND l.name = 'Porto' AND a.area >= 100 AND a.price >= 200000 AND a.price <= 300000
  RETURN a
  "

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
    puts my_system_message
    cql = get_openai_response(user_input, my_system_message)
    cql
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
    # results = query_neo4j(cql)
    # explanation = generate_explanation(results)
  
    cql
  end

end
