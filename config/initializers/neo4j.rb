require 'neo4j_ruby_driver'

ActiveGraph::Base.driver = Neo4j::Driver::GraphDatabase.driver(
  ENV['NEO4J_URL'] || 'bolt://127.0.0.1:7687', 
  Neo4j::Driver::AuthTokens.basic(ENV['NEO4J_USERNAME'], ENV['NEO4J_PASSWORD'])
)

