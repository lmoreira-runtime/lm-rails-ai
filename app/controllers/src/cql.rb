
def clean_cql_query(cql_query)
    cql_query = cql_query.gsub(/```.*?\n|```/, '')
    cleaned_query = cql_query.lines.map(&:strip)
    cleaned_query.reject! { |line| line.empty? || line.start_with?('//', '#') }
    cleaned_query.join(' ')
end


def extract_patterns(cql_query)
    normalized_query = cql_query.gsub(/\s+/, ' ')
  
    result = []
  
    forward_pattern = /\((\w+)(?::(\w+))?\)-\[:(\w+)\]->\((\w+)(?::(\w+))?\)/
    reverse_pattern = /\((\w+)(?::(\w+))?\)<-\[:(\w+)\]-\((\w+)(?::(\w+))?\)/
  
    offset = 0
  
    while offset < normalized_query.length
      forward_match = normalized_query.match(forward_pattern, offset)
      reverse_match = normalized_query.match(reverse_pattern, offset)
  
      if forward_match && (!reverse_match || forward_match.begin(0) < reverse_match.begin(0))
        result << forward_match.captures + ['->']
        offset = forward_match.end(0)
      elsif reverse_match
        result << reverse_match.captures + ['<-']
        offset = reverse_match.end(0)
      else
        break
      end
    end
  
    result
end
  


def validate_relationships(cql_query, db_relationships)
    result = { "valid": nil, "errors": [], "corrections": [] }
    nodes_n_labels = {}
    patterns = extract_patterns(cql_query)
    # puts "# Patterns: #{patterns.inspect}\n"
    relationships = parse_json_with_bom_removal(db_relationships)

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
        # puts "#### (#{node1}:#{label1})-[:#{rel_type}]->(#{node2}:#{label2})"
        # else
        # puts "#### (#{node1}:#{label1})<-[:#{rel_type}]-(#{node2}:#{label2})"
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
        # puts "### (#{before_end})<-[:#{before_rel}]-(#{before_start})"
        before_pattern = /
            \(\s*(\w*)\s*(?::#{before_end})?\s*\)\s*
            <-\[:#{before_rel}\]-\s*
            \(\s*(\w*)\s*(?::#{before_start})?\s*\)
        /x
    else
        # puts "### (#{before_start})-[:#{before_rel}]->(#{before_end})"
        before_pattern = /
            \(\s*(\w*)\s*(?::#{before_start})?\s*\)\s*
            -\[:#{before_rel}\]->\s*
            \(\s*(\w*)\s*(?::#{before_end})?\s*\)
        /x
    end

    if before_start == after_end && before_end == after_start
        # puts "# before_start == after_end && before_end == after_start"
        after_pattern = if query.include?("<-[:#{after_rel}]-")
            "(\\1:#{after_start})-[:#{after_rel}]->(\\2:#{after_end})"
        else
            "(\\1:#{after_end})<-[:#{after_rel}]-(\\2:#{after_start})"
        end
    else
        # puts "# not a direction problem"
        after_pattern = if query.include?("<-[:#{after_rel}]-")
            "(\\1:#{after_start})<-[:#{after_rel}]-(\\2:#{after_end})"
        else
            "(\\1:#{after_start})-[:#{after_rel}]->(\\2:#{after_end})"
        end
    end

    query.gsub!(before_pattern, after_pattern)
end

query
end

def determine_query_complexity(query_structure)
    weights = {
      action: { "list" => 1, "count" => 2, "find" => 3, "change" => -10000 },
      entities: 1,
      relationships: 2,
      conditions: 2,
      sorting: 1,
      output: 1,
      aggregation: 3,
      nested: 4
    }

    # puts "Query structure: #{query_structure.inspect}"
  
    action = query_structure["action"]
    entities = query_structure["entities"] || []
    relationships = query_structure["relationships"] || []
    conditions = query_structure["conditions"] || {}
    sorting = query_structure["sorting"]
    output = query_structure["output"] || []
    aggregation = query_structure["aggregation"]
    nested = query_structure["nested"]

    # puts "Action: #{action.inspect}"
    # puts "Entities: #{entities.inspect}"
    # puts "Relationships: #{relationships.inspect}"
    # puts "Conditions: #{conditions.inspect}"
    # puts "Sorting: #{sorting.inspect}"
    # puts "Output: #{output.inspect}"
  
    action_score = weights[:action][action] if weights[:action].key?(action)
    entities_score = entities.size * weights[:entities]
    relationships_score = relationships.size * weights[:relationships]
    conditions_score = conditions.size * weights[:conditions]
    sorting_score = sorting.present? ? weights[:sorting] : 0
    outputs_score = output.size * weights[:output]
    aggregation_score = aggregation ? weights[:aggregation] : 0
    nested_score = nested ? weights[:nested] : 0
    
    # puts "Action score (#{action}): #{action_score}"
    # puts "entities score (#{entities.size}) entities: #{entities_score}"
    # puts "relationships score (#{relationships.size}) relationships: #{relationships_score}"
    # puts "conditions score (#{conditions.size}) conditions: #{conditions_score}"
    # puts "sorting score (#{sorting}) sorting: #{sorting_score}"
    # puts "output score (#{output.size}) output: #{outputs_score}"
    
    complexity_score = 0
    complexity_score += action_score
    complexity_score += entities_score
    complexity_score += relationships_score
    complexity_score += conditions_score
    complexity_score += sorting_score
    complexity_score += outputs_score
    complexity_score += aggregation_score
    complexity_score += nested_score

    puts "# Complexity score: #{complexity_score}"
  
    # Normalize the score to a 1-5 scale
    case complexity_score
    when -100000..-1
      nil
    when 0..5
      1 # Very Simple
    when 6..10
      2 # Simple
    when 11..15
      3 # Moderate
    when 16..20
      4 # Complex
    else
      5 # Very Complex
    end
end
