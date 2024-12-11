require './config/initializers/neo4j'
require './app/controllers/src/json'
require './app/controllers/src/procedures'

def generate_query_lvl4(user_request, extracted_components)
    mapping = map_data_model(user_request, extracted_components)
    reasoning = reason_on_request_and_mapping(user_request, mapping)
    generated_query = translate_to_cql_with_reasoning(user_request, mapping, reasoning)
    cypher_result = aproximate_to_user_expectation(user_request, extracted_components, generated_query, 5)
    cypher_result[:query]
end