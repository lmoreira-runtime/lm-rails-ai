require 'neo4j_ruby_driver'
require './config/initializers/neo4j'
require './app/models/question'

class QuestionsController < ApplicationController
  def new
    # Render the file upload form
  end

  def create
    # Ensure the global Neo4j driver is initialized
    driver = $neo4j_driver
    if driver.nil?
      raise RuntimeError, "Neo4j driver is not initialized!"
    end
  
    # Open a session and log its details
    session = driver.session
    # puts "Driver: #{driver.inspect}"
    # puts "Session: #{session.inspect}"
  
    begin
      # Get and split the questions text
      questions_text = params[:questions]&.strip
      if questions_text.blank?
        redirect_to questions_path, alert: "No questions provided!"
        return
      end
  
      questions = questions_text.split("\n").map(&:strip).reject(&:empty?)
  
      # Create a new question for each non-empty line
      questions.each do |q_text|
        session.write_transaction do |tx|
          tx.run("CREATE (q:Question {question: $text, processed: false, to_be_processed: true})", text: q_text)
        end
      end
  
      redirect_to questions_path, notice: "#{questions.size} questions imported successfully!"
    ensure
      session.close if session
    end
  end
  
  def index
    driver = $neo4j_driver
    session = driver.session
    @questions = session.run("MATCH (q:Question {processed: false}) RETURN q").map do |record|
      record['q']
    end
  ensure
    session&.close
  end

  def preprocess
    driver = $neo4j_driver
    session = driver.session
    @questions = session.run("MATCH (q:Question {to_be_processed: true}) RETURN q").map do |record|
      record['q']
    end
  ensure
    session&.close
  end

  def start
    job = ProcessQuestionsTaskJob.perform_later
    job_id = job.job_id
    puts "Job created: #{job.inspect}"
    puts "Job ID: #{job_id}"
    render json: { job_id: job_id }
  end

  def status
    job_id = params[:job_id]
    puts "Job ID: #{job_id}"
    # job = Sidekiq::Job.find(job_id)
    # puts "Job: #{job.inspect}"
    status = Rails.cache.read("job_status_#{job_id}")
    puts ">>>>>   Status: #{status.inspect}"
    render json: { status: status || "unknown" } # Return "unknown" if the status is nil
  end

end
