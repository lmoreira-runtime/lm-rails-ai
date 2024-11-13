require './app/controllers/src/cql'

query="```cypher
MATCH (a:Apartamento)-[:LOCATED_IN]->(l:Location), 
      (a)-[:OF_TYPE]->(t:Type) 
RETURN l.name AS location, t.name AS apartment_type, COUNT(a) AS count 
ORDER BY location, count DESC
```"

puts clean_cql_query(query)