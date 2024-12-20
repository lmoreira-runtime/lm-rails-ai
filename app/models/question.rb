class Question
  include Neo4j::ActiveNode

  property :id, type: Integer, constraint: :unique
  property :question, type: String
  property :processed, type: Boolean, default: false
  property :to_be_processed, type: Boolean, default: true
end