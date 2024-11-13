
def query_neo4j(cql)
    session = ActiveGraph::Base.driver.session
    begin
        result = session.run(cql)
        nodes = result.to_a
    rescue => e
        puts("ERROR: #{e}")
        {
            "result": nil,
            "error": e
        }
    else
        puts("# Nodes: #{nodes.length}")
        {
            "result": nodes,
            "error": nil
        }
    ensure
        session.close
    end
end