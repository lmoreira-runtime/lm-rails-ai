require './app/controllers/src/cql'
require './app/controllers/src/lvl1'
require './app/controllers/src/lvl2'
require './app/controllers/src/lvl3'
require './app/controllers/src/lvl4'
require './app/controllers/src/lvl5'
require './app/controllers/src/prompts'
require './app/controllers/src/procedures'

def query_generation(user_input)
  extracted_components = analyze_user_request(user_input)
  extracted_components_hash = parse_json_with_bom_removal(extracted_components)
  complexity = determine_query_complexity(extracted_components_hash)

  case complexity
  when 1
    puts "** LEVEL 1 **"
    generated_query = generate_query_lvl1(user_input, extracted_components_hash)
  when 2
    puts "** LEVEL 2 **"
    generated_query = generate_query_lvl2(user_input, extracted_components_hash)
  when 3
    puts "** LEVEL 3 **"
    generated_query = generate_query_lvl3(user_input, extracted_components_hash)
  when 4
    puts "** LEVEL 4 **"
    generated_query = generate_query_lvl4(user_input, extracted_components_hash)
  when 5
    puts "** LEVEL 5 **"
    generated_query = generate_query_lvl5(user_input, extracted_components_hash)
  else
    generated_query = "ERROR: operation not permitted"
  end

  generated_query
end