require './app/jobs/src/process_questions'

class ProcessQuestionsTaskJob < ApplicationJob
  queue_as :default

  def perform
    # Mark as processing
    Rails.cache.write("job_status_#{self.job_id}", "processing")
    
    process_questions
    
    # Mark as completed
    Rails.cache.write("job_status_#{self.job_id}", "completed")
  end
end
