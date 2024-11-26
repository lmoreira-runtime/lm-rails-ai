require 'json'

def parse_json_with_bom_removal(json_string)
# Remove BOM if it exists
json_string = json_string.sub("\uFEFF", '')
JSON.parse(json_string)
end