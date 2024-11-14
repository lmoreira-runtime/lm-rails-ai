############
require './app/controllers/src/cql'
require './app/controllers/src/json'

db_relationships = "[
  {
    \"RelationshipType\": \"OF_TYPE\",
    \"StartNodeLabels\": [
      \"Apartamento\"
    ],
    \"EndNodeLabels\": [
      \"Type\"
    ]
  },
  {
    \"RelationshipType\": \"LOCATED_IN\",
    \"StartNodeLabels\": [
      \"Apartamento\"
    ],
    \"EndNodeLabels\": [
      \"Location\"
    ]
  },
  {
    \"RelationshipType\": \"WORKS_IN\",
    \"StartNodeLabels\": [
      \"RealEstateAgent\"
    ],
    \"EndNodeLabels\": [
      \"Location\"
    ]
  },
  {
    \"RelationshipType\": \"REPRESENTS\",
    \"StartNodeLabels\": [
      \"RealEstateAgent\"
    ],
    \"EndNodeLabels\": [
      \"Owner\"
    ]
  },
  {
    \"RelationshipType\": \"OWNS\",
    \"StartNodeLabels\": [
      \"Owner\"
    ],
    \"EndNodeLabels\": [
      \"Apartamento\"
    ]
  },
  {
    \"RelationshipType\": \"HAS_AMENITY\",
    \"StartNodeLabels\": [
      \"Apartamento\"
    ],
    \"EndNodeLabels\": [
      \"Amenity\"
    ]
  }
]"

query = "MATCH (a:Apartamento)-[:LOCATED_IN]->(l:Location),
      (a)<-[:OWNS]-(o:Owner),
      (ra:RealEstateAgent)-[:REPRESENTS]->(o:Owner),
      (ra)-[:WORKS_IN]->(l),
      (a:Apartamento)-[:HAS_AMENITY]->(amenity:Amenity)
WITH a, l, ra, COUNT(amenity) AS amenityCount
WHERE amenityCount >= 3
WITH l, AVG(a.price) AS avgPrice
MATCH (a:Apartamento)-[:LOCATED_IN]->(l:Location),
      (a)<-[:OWNS]-(o:Owner),
      (ra:RealEstateAgent)-[:REPRESENTS]->(o:Owner),
      (ra:RealEstateAgent)<-[:WORKS_IN]-(l:Location)
WHERE a.price < avgPrice
RETURN a, l, ra 
LIMIT 10
"

puts "### QUERY: #{query}\n"

val = validate_relationships(query, db_relationships)
puts val

puts fix_relationships(query, val[:corrections])
