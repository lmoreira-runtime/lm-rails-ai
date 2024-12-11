require './config/initializers/neo4j'
require './app/controllers/src/json'
require './app/controllers/src/procedures'

def generate_query_lvl5(user_request, extracted_components)
    explanation = explain_user_request(user_request)
    mapping = map_data_model(user_request, extracted_components)
    reasoning = reason_on_request_and_mapping(explanation, mapping)
    generated_query = translate_to_cql_with_reasoning(explanation, mapping, reasoning)
    cypher_result = aproximate_to_user_expectation(user_request, extracted_components, generated_query, 5)
    cypher_result[:query]
end