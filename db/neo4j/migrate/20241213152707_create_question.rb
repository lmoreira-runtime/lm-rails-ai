class CreateQuestion < ActiveGraph::Migrations::Base
  disable_transactions!

  def up
    add_constraint :Question, :uuid
  end

  def down
    drop_constraint :Question, :uuid
  end
end
