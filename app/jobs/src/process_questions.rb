require 'neo4j_ruby_driver'
require './config/initializers/neo4j'
require './app/models/question'
require './app/controllers/src/query_generation'

def process_questions
  # Get all questions to be processed from the database
  begin
    driver = $neo4j_driver
    session = driver.session
    @questions = session.run("MATCH (q:Question {to_be_processed: true}) RETURN q").map do |record|
      puts "\nQuestion: #{record['q'].properties[:question]}"
      generated_query = query_generation(record['q'].properties[:question])
      puts "Generated query: #{generated_query}\n"
      session.write_transaction do |tx|
        tx.run("CREATE (rq:Result_Query {query: $text, datetime: datetime(), llm_evaluated: false, manually_evaluated: false})
        WITH rq
        MATCH (q:Question)
        WHERE ID(q) = $qid
        CREATE (rq)-[:RESULT_OF]->(q)", text: generated_query, qid: record['q'].id)
      end
      session.write_transaction do |tx2|
        tx2.run("MATCH (q:Question)
        WHERE ID(q) = $qid SET 
        q.to_be_processed = false,
        q.processed = true", qid: record['q'].id)
      end
    end
  ensure
    session&.close
  end
end