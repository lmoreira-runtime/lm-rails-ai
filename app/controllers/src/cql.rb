
def clean_cql_query(cql_query)
    cql_query = cql_query.gsub(/```.*?\n|```/, '')
    cleaned_query = cql_query.lines.map(&:strip)
    cleaned_query.reject! { |line| line.empty? || line.start_with?('//', '#') }
    cleaned_query.join(' ')
end


def extract_patterns(cql_query)
# Normalize spaces for consistent matching
normalized_query = cql_query.gsub(/\s+/, ' ')
#puts "Normalized Query: #{normalized_query}"

result = []

forward_pattern = /\((\w+)(?::(\w+))?\)-\[:(\w+)\]->\((\w+)(?::(\w+))?\)/
reverse_pattern = /\((\w+)(?::(\w+))?\)<-\[:(\w+)\]-\((\w+)(?::(\w+))?\)/

# Traverse the query string with overlapping matches
offset = 0
while offset < normalized_query.length
    match = normalized_query.match(forward_pattern, offset) || normalized_query.match(reverse_pattern, offset)

    if match
    result << match.captures + (match[0].include?('->') ? ['->'] : ['<-'])
    # Move the offset forward to allow overlapping matches
    offset = match.begin(0) + 1
    else
    break
    end
end

# Log results for debugging
#puts "Matches: #{result.inspect}"
result
end


def validate_relationships(cql_query, db_relationships)
result = { "valid": nil, "errors": [], "corrections": [] }
nodes_n_labels = {}
patterns = extract_patterns(cql_query)
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

    if direction == '->'
    puts "#### (#{node1}:#{label1})-[:#{rel_type}]->(#{node2}:#{label2})"
    else
    puts "#### (#{node1}:#{label1})<-[:#{rel_type}]-(#{node2}:#{label2})"
    end

    puts "# nodes_n_labels: #{nodes_n_labels.inspect}"

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
    before_pattern = /
        \(\s*(\w*)\s*(?::#{before_end})?\s*\)\s*
        <-\[:#{before_rel}\]-\s*
        \(\s*(\w*)\s*(?::#{before_start})?\s*\)
    /x
    else
    before_pattern = /
        \(\s*(\w*)\s*(?::#{before_start})?\s*\)\s*
        -\[:#{before_rel}\]->\s*
        \(\s*(\w*)\s*(?::#{before_end})?\s*\)
    /x
    end

    if before_start == after_end && before_end == after_start
        after_pattern = if query.include?("<-[:#{after_rel}]-")
            "(\\1:#{after_start})-[:#{after_rel}]->(\\2:#{after_end})"
        else
            "(\\1:#{after_end})<-[:#{after_rel}]-(\\2:#{after_start})"
        end
    else
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