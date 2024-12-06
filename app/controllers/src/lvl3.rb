require './config/initializers/neo4j'
require './app/controllers/src/json'
require './app/controllers/src/procedures'

def generate_query_lvl3(user_request, extracted_components)
    generated_query = translate_to_cql(user_request, extracted_components)
    cypher_result = aproximate_to_user_expectation(user_request, extracted_components, generated_query, 4)
    cypher_result[:query]
end