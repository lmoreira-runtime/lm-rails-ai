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
  You are an AI assistant for a real estate search platform. The database has three key entities: 'Apartamento,' 'Type,' and 'Location.' The 'Apartamento' entity represents apartments, and each apartment is associated with a 'Type' (such as T0, T1, T2, etc.), a 'Location' (e.g., specific cities or neighborhoods), an area (in square meters), and a price (in the chosen currency).
  
  Your task is to analyze the user's request and identify the filtering parameters related to apartment type, location, area, and price. Return a JSON object with four fields: 'type,' 'location,' 'area,' and 'price.' If any of these fields are not explicitly mentioned in the user’s request, return them as null. For area and price, handle ranges if the user specifies them. If there are multiple matching options, list them as an array.
  
  **Example input:**
  \"I am looking for a two-bedroom apartment in Lisbon, between 80-100 square meters, and under 300,000 euros.\"
  
  **Expected JSON output:**
  {
    \"type\": [\"T2\"],
    \"location\": [\"Lisbon\"],
    \"area\": {\"min\": 80, \"max\": 100},
    \"price\": {\"max\": 300000}
  }
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
    llm_filters = get_openai_response(user_input, @@request_system_message)
    filters = JSON.parse(llm_filters)

    apartment_type = filters['type']
    location = filters['location']
    area_min = filters.dig('area', 'min')
    area_max = filters.dig('area', 'max')
    price_min = filters.dig('price', 'min')
    price_max = filters.dig('price', 'max')

    cql = "
    MATCH (a:Apartamento)-[:OF_TYPE]->(t:Type), 
    (a)-[:LOCATED_IN]->(l:Location)
    where 1=1"

    if apartment_type 
      cql += " AND t.name IN ['" + apartment_type.join(',') + "']" 
    end
    if location 
      cql += " AND l.name IN ['" + location.join(',') + "']"
    end
    if area_min 
      cql += " AND a.area >= " + area_min.to_s
    end
    if area_max 
      cql += " AND a.area <= " + area_max.to_s
    end
    if price_min 
      cql += " AND a.price >= " + price_min.to_s
    end
    if price_max 
      cql += " AND a.price <= " + price_max.to_s
    end
    cql += " RETURN a"
    puts cql
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
    results = query_neo4j(cql)
    explanation = generate_explanation(results)
  
    explanation
  end

end
