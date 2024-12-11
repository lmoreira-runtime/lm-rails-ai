require './config/initializers/neo4j'
require './app/controllers/src/prompts'
require './app/controllers/src/cql'
require './app/controllers/src/llms'
require './app/controllers/src/json'

def translate_to_cql(user_input, extracted_components, mapping = nil)
    db_nodes = Neo4jSchema.db_nodes
    db_relationships = Neo4jSchema.db_relationships
    prompt_result_example ||= File.read(ENV['PROMPT_RESULT_EXAMPLE_PATH'])
    if mapping
        my_system_message = $translate_to_cql_with_mapping_system_message
    else
        my_system_message = $translate_to_cql_system_message
    end
    my_system_message = my_system_message.sub("###NODES###", db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", db_relationships)
    my_system_message = my_system_message.sub("###EXAMPLE###", prompt_result_example)
    my_user_message = "**User Request**: #{user_input}\n\n**Extracted Components**: #{extracted_components}"
    if mapping
        my_user_message += "\n\n**Mapped Components**: #{mapping}"
    end
    generated_query = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    cql = clean_cql_query(generated_query)
    puts ("# CQL: #{cql}\n")
    cql
end

def analyze_cql_query(user_message, extracted_components, generated_query)
    my_system_message = $analyze_system_message
    my_user_message = "**User Message**: #{user_message}\n\n**Extracted Components**: #{extracted_components}\n\n**Generated Query**: #{generated_query}"
    result_analysis = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    puts "# QUERY ANALYSIS: #{result_analysis}\n"
    result = parse_json_with_bom_removal(result_analysis)
    result
end

def fix_cql_to_meet_expectation(user_message, unreliable_query, guidance)
    db_nodes = Neo4jSchema.db_nodes
    db_relationships = Neo4jSchema.db_relationships
    my_system_message = $meet_expectation_system_message
    my_system_message = my_system_message.sub("###NODES###", db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", db_relationships)
    my_user_message = "**User Request**: #{user_message}\n\n**Unreliable Query**: #{unreliable_query}\n\n**Guidance**: #{guidance}"
    result_query = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    cql = clean_cql_query(result_query)
    puts "# (UN)RELIABLE QUERY: #{cql}\n"
    cql
end

def aproximate_to_user_expectation(user_message, extracted_components, generated_query, number_of_tries = 4)
    reliable_query = generated_query
    num_tries = number_of_tries
    analysis = analyze_cql_query(user_message, extracted_components, reliable_query)
    while analysis["valid"] == false && num_tries > 0
      num_tries -= 1
      reliable_query = fix_cql_to_meet_expectation(user_message, reliable_query, analysis["comment"])
      analysis = analyze_cql_query(user_message, extracted_components, reliable_query)
    end
    {
        "valid": analysis["valid"],
        "query": reliable_query
    }
end

def map_data_model(user_input, extracted_components)
    db_nodes = Neo4jSchema.db_nodes
    db_relationships = Neo4jSchema.db_relationships
    my_system_message = $map_data_model_system_message
    my_system_message = my_system_message.sub("###NODES###", db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", db_relationships)
    my_user_message = "**User Request**: #{user_input}\n\n**Extracted Components**: #{extracted_components}"
    result_mapping = get_openai_response(user_input, my_system_message, "gpt-4o-mini")
    # result = get_ollama_response(my_user_message, my_system_message, "llama3.1")
    puts ("# MAPPING: #{result_mapping}\n")
    result_mapping
end

def reason_on_request_and_mapping(user_request, mapping)
    my_system_message = $reason_on_request_and_mapping
    my_user_message = "**User Request**: #{user_request}"
    my_user_message += "\n\n**Mapped Components**: #{mapping}"
    result_reasoning = get_openai_response(my_user_message, my_system_message, "gpt-4o-mini")
    puts ("# REASONING: #{result_reasoning}\n")
    result_reasoning
end

def translate_to_cql_with_reasoning(user_input, mapped_components, reasoning)
    my_system_message = $translate_to_cql_with_reasoning_system_message
    my_user_message = "**User Request**: #{user_input}"
    my_user_message += "\n\n**Mapped Components**: #{mapped_components}"
    my_user_message += "\n\n**Reasoning**: #{reasoning}"
    generated_query = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    cql = clean_cql_query(generated_query)
    puts ("# CQL: #{cql}\n")
    cql
end

def explain_user_request(user_request)
    db_nodes = Neo4jSchema.db_nodes
    db_relationships = Neo4jSchema.db_relationships
    my_system_message = $explain_user_request_system_message
    my_system_message = my_system_message.sub("###NODES###", db_nodes)
    my_system_message = my_system_message.sub("###RELATIONSHIPS###", db_relationships)
    my_user_message = user_request
    explanation = get_openai_response(my_user_message, my_system_message, "gpt-4o")
    puts ("# EXPLANATION: #{explanation}\n")
    explanation
end