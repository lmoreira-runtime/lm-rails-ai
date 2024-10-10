require 'neo4j_ruby_driver'

ActiveGraph::Base.driver = Neo4j::Driver::GraphDatabase.driver(
  ENV['NEO4J_URL'] || 'bolt://127.0.0.1:7687', 
  Neo4j::Driver::AuthTokens.basic(ENV['NEO4J_USERNAME'], ENV['NEO4J_PASSWORD'])
)


module Neo4jSchema
  def self.db_nodes
    @db_nodes ||= File.read(ENV['NEO4J_NODES_PATH'])
  end

  def self.db_relationships
    @db_relationships ||= File.read(ENV['NEO4J_RELATIONSHIPS_PATH'])
  end
end