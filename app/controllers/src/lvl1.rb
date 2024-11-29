require './config/initializers/neo4j'
require './app/controllers/src/llms'

def translate_to_cql_lvl1(user_input)
    db_nodes = Neo4jSchema.db_nodes
    db_relationships = Neo4jSchema.db_relationships
    my_system_message = "
    You are an expert in Cypher (CQL) and highly efficient at transforming natural language requests into precise queries for a Neo4j database.

    **DATABASE_SCHEMA**

    This is a JSON describing the database nodes: ###NODES###

    This is a JSON describing the database relationships between nodes, including their directionality: ###RELATIONSHIPS###

    Your task is to:

    1. Analyze the user request to understand the desired information.
    2. Ensure strict adherence to relationship direction as specified in the database schema.
    3. Translate the user's request into a valid CQL query. The query must accurately reflect the direction of relationships. The properties must match the ones defined in the schema.
    4. Generate only a valid Cypher query (CQL). Provide the query as plain text with no leading or trailing characters, and no code block delimiters.
    "
    my_system_message = my_system_message.sub("###NODES###", db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", db_relationships)
    cql = get_openai_response(user_input, my_system_message, "gpt-4o")
    puts ("# CQL: #{cql}\n")
    cql
end

def generate_query_lvl1(user_request, extracted_components)
    cql = translate_to_cql_lvl1(user_request)
    cql
end