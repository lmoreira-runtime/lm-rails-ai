require './config/initializers/neo4j'
require './app/controllers/src/llms'
require './app/controllers/src/procedures'

def generate_query_lvl1(user_request, extracted_components)
    generated_query = translate_to_cql(user_request, extracted_components)
    generated_query
end